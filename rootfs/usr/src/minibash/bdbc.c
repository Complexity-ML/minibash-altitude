#define _GNU_SOURCE
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#define VERSION "0.3.0-native"
#define BDB_MAGIC "BDB1"

typedef struct { char *name; char *type; bool pk; } Column;
typedef struct { Column *cols; size_t len; int pk_idx; } Schema;
typedef struct { char *col; char *val; } Assign;
typedef struct { char ***rows; size_t len; } RowSet;

static void die(const char *fmt, ...) {
  va_list ap;
  fprintf(stderr, "bdbc: ");
  va_start(ap, fmt);
  vfprintf(stderr, fmt, ap);
  va_end(ap);
  fputc('\n', stderr);
  exit(1);
}

static char *xstrdup(const char *s) {
  char *p = strdup(s ? s : "");
  if (!p) die("out of memory");
  return p;
}

static char *xasprintf(const char *fmt, ...) {
  va_list ap;
  char *out = NULL;
  va_start(ap, fmt);
  if (vasprintf(&out, fmt, ap) < 0) die("out of memory");
  va_end(ap);
  return out;
}

static const char *db_dir(void) {
  const char *p = getenv("BDB_PATH");
  return (p && *p) ? p : ".bdb";
}

static bool is_name(const char *s) {
  if (!s || !*s) return false;
  if (!(isalpha((unsigned char)s[0]) || s[0] == '_')) return false;
  for (size_t i = 1; s[i]; i++) {
    if (!(isalnum((unsigned char)s[i]) || s[i] == '_')) return false;
  }
  return true;
}

static bool exists_dir(const char *p) {
  struct stat st;
  return stat(p, &st) == 0 && S_ISDIR(st.st_mode);
}

static char *table_dir(const char *table) { return xasprintf("%s/tables/%s", db_dir(), table); }
static char *schema_path(const char *table) { return xasprintf("%s/schema.bdb", table_dir(table)); }
static char *data_path(const char *table) { return xasprintf("%s/data.bdb", table_dir(table)); }

static void mkdir_p(const char *path) {
  char tmp[PATH_MAX];
  snprintf(tmp, sizeof(tmp), "%s", path);
  for (char *p = tmp + 1; *p; p++) {
    if (*p == '/') { *p = 0; mkdir(tmp, 0755); *p = '/'; }
  }
  if (mkdir(tmp, 0755) && errno != EEXIST) die("mkdir %s: %s", path, strerror(errno));
}

static void require_db(void) {
  char *p = xasprintf("%s/tables", db_dir());
  bool ok = exists_dir(p);
  free(p);
  if (!ok) die("base introuvable: %s (lance: bdb init)", db_dir());
}

static void require_table(const char *table) {
  char *p = table_dir(table);
  bool ok = exists_dir(p);
  free(p);
  if (!ok) die("table introuvable: %s", table);
}

static void write_u32(FILE *f, uint32_t v) {
  unsigned char b[4] = {(unsigned char)(v & 255), (unsigned char)((v >> 8) & 255), (unsigned char)((v >> 16) & 255), (unsigned char)((v >> 24) & 255)};
  if (fwrite(b, 1, 4, f) != 4) die("write failed");
}

static uint32_t read_u32(FILE *f) {
  unsigned char b[4];
  if (fread(b, 1, 4, f) != 4) die("native read failed");
  return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
}

static void write_str(FILE *f, const char *s) {
  size_t n = strlen(s);
  if (n > UINT32_MAX) die("field too large");
  write_u32(f, (uint32_t)n);
  if (n && fwrite(s, 1, n, f) != n) die("write failed");
}

static char *read_str(FILE *f) {
  uint32_t n = read_u32(f);
  char *s = calloc((size_t)n + 1, 1);
  if (!s) die("out of memory");
  if (n && fread(s, 1, n, f) != n) die("native read failed");
  return s;
}

static void write_magic(FILE *f) {
  if (fwrite(BDB_MAGIC, 1, 4, f) != 4) die("write failed");
}

static void read_magic(FILE *f, const char *path) {
  char magic[4];
  if (fread(magic, 1, 4, f) != 4 || memcmp(magic, BDB_MAGIC, 4) != 0) die("format natif invalide: %s", path);
}

static void free_schema(Schema *s) {
  for (size_t i = 0; i < s->len; i++) { free(s->cols[i].name); free(s->cols[i].type); }
  free(s->cols);
}

static Schema load_schema(const char *table) {
  char *path = schema_path(table);
  FILE *f = fopen(path, "rb");
  if (!f) die("schema natif introuvable: %s", path);
  read_magic(f, path);
  uint32_t version = read_u32(f), cols = read_u32(f), pk_idx = read_u32(f);
  if (version != 1) die("schema natif incompatible: %s", path);
  Schema s = {.len = cols, .pk_idx = pk_idx == UINT32_MAX ? -1 : (int)pk_idx};
  s.cols = calloc(s.len, sizeof(Column));
  if (!s.cols && s.len) die("out of memory");
  for (size_t i = 0; i < s.len; i++) {
    s.cols[i].name = read_str(f);
    s.cols[i].type = read_str(f);
    s.cols[i].pk = read_u32(f) == 1;
  }
  fclose(f);
  free(path);
  return s;
}

static void write_schema(const char *table, const Schema *s) {
  char *td = table_dir(table), *path = schema_path(table), *tmp = xasprintf("%s/.schema.bdb.tmp", td);
  FILE *f = fopen(tmp, "wb");
  if (!f) die("open %s: %s", tmp, strerror(errno));
  write_magic(f); write_u32(f, 1); write_u32(f, (uint32_t)s->len); write_u32(f, s->pk_idx < 0 ? UINT32_MAX : (uint32_t)s->pk_idx);
  for (size_t i = 0; i < s->len; i++) { write_str(f, s->cols[i].name); write_str(f, s->cols[i].type); write_u32(f, s->cols[i].pk ? 1 : 0); }
  fclose(f);
  if (rename(tmp, path) != 0) die("rename %s: %s", path, strerror(errno));
  free(tmp); free(path); free(td);
}

static void free_row(char **row, size_t cols) {
  for (size_t i = 0; i < cols; i++) free(row[i]);
  free(row);
}

static void free_rowset(RowSet *rs, size_t cols) {
  for (size_t i = 0; i < rs->len; i++) free_row(rs->rows[i], cols);
  free(rs->rows);
}

static RowSet read_rows(const char *table, const Schema *s) {
  char *path = data_path(table);
  FILE *f = fopen(path, "rb");
  if (!f) die("data natif introuvable: %s", path);
  read_magic(f, path);
  uint32_t version = read_u32(f), cols = read_u32(f), rows = read_u32(f);
  if (version != 1 || cols != s->len) die("data natif incompatible: %s", path);
  RowSet rs = {.len = rows, .rows = calloc(rows, sizeof(char **))};
  if (!rs.rows && rows) die("out of memory");
  for (size_t r = 0; r < rs.len; r++) {
    rs.rows[r] = calloc(s->len, sizeof(char *));
    if (!rs.rows[r]) die("out of memory");
    for (size_t c = 0; c < s->len; c++) rs.rows[r][c] = read_str(f);
  }
  fclose(f);
  free(path);
  return rs;
}

static void write_rows(const char *table, const Schema *s, const RowSet *rs) {
  char *td = table_dir(table), *path = data_path(table), *tmp = xasprintf("%s/.data.bdb.tmp", td);
  FILE *f = fopen(tmp, "wb");
  if (!f) die("open %s: %s", tmp, strerror(errno));
  write_magic(f); write_u32(f, 1); write_u32(f, (uint32_t)s->len); write_u32(f, (uint32_t)rs->len);
  for (size_t r = 0; r < rs->len; r++) for (size_t c = 0; c < s->len; c++) write_str(f, rs->rows[r][c]);
  fclose(f);
  if (rename(tmp, path) != 0) die("rename %s: %s", path, strerror(errno));
  free(tmp); free(path); free(td);
}

static int col_index(const Schema *s, const char *name) {
  for (size_t i = 0; i < s->len; i++) if (strcmp(s->cols[i].name, name) == 0) return (int)i;
  return -1;
}

static bool validate_type(const char *type, const char *val) {
  if (strcmp(type, "text") == 0 || strcmp(type, "string") == 0) return true;
  if (strcmp(type, "bool") == 0) return !strcmp(val, "true") || !strcmp(val, "false") || !strcmp(val, "1") || !strcmp(val, "0");
  char *end = NULL; errno = 0;
  if (strcmp(type, "int") == 0) { strtol(val, &end, 10); return errno == 0 && end && *end == 0; }
  if (strcmp(type, "real") == 0) { strtod(val, &end); return errno == 0 && end && *end == 0; }
  die("type inconnu: %s", type);
  return false;
}

static Assign parse_assign(const char *s) {
  const char *eq = strchr(s, '=');
  if (!eq) die("affectation attendue: COL=VALUE");
  Assign a = {.col = strndup(s, (size_t)(eq - s)), .val = xstrdup(eq + 1)};
  if (!a.col) die("out of memory");
  if (!is_name(a.col)) die("nom de colonne invalide: %s", a.col);
  return a;
}

static void free_assigns(Assign *a, size_t n) {
  for (size_t i = 0; i < n; i++) { free(a[i].col); free(a[i].val); }
  free(a);
}

static char *assignment_value(const char *col, Assign *a, size_t n) {
  for (size_t i = 0; i < n; i++) if (strcmp(a[i].col, col) == 0) return a[i].val;
  return NULL;
}

static bool row_matches(char **row, const Schema *s, const char *col, const char *val) {
  if (!col) return true;
  int idx = col_index(s, col);
  if (idx < 0) die("colonne inconnue: %s", col);
  return strcmp(row[idx], val) == 0;
}

static void lock_db(void) {
  char *lock = xasprintf("%s/.lock", db_dir());
  for (int i = 0; i < 50; i++) { if (mkdir(lock, 0755) == 0) { free(lock); return; } usleep(100000); }
  die("verrou occupe: %s", db_dir());
}

static void unlock_db(void) {
  char *lock = xasprintf("%s/.lock", db_dir());
  rmdir(lock);
  free(lock);
}

static void cmd_init(int argc, char **argv) {
  const char *dir = argc > 0 ? argv[0] : db_dir();
  char *tables = xasprintf("%s/tables", dir), *version = xasprintf("%s/VERSION", dir);
  mkdir_p(tables);
  FILE *f = fopen(version, "w");
  if (!f) die("open %s: %s", version, strerror(errno));
  fprintf(f, "%s\n", VERSION);
  fclose(f);
  printf("base initialisee: %s\n", dir);
  free(tables); free(version);
}

static void cmd_tables(void) {
  require_db();
  char *p = xasprintf("%s/tables", db_dir());
  DIR *d = opendir(p);
  if (!d) die("opendir %s: %s", p, strerror(errno));
  struct dirent *e;
  while ((e = readdir(d))) {
    if (e->d_name[0] == '.') continue;
    char *td = xasprintf("%s/%s", p, e->d_name);
    if (exists_dir(td)) puts(e->d_name);
    free(td);
  }
  closedir(d); free(p);
}

static void cmd_schema(const char *table) {
  require_db(); require_table(table);
  Schema s = load_schema(table);
  for (size_t i = 0; i < s.len; i++) printf("%s\t%s\t%s\n", s.cols[i].name, s.cols[i].type, s.cols[i].pk ? "pk" : "");
  free_schema(&s);
}

static void cmd_create(int argc, char **argv) {
  if (argc < 2) die("usage: bdb create TABLE COL:TYPE[:pk]...");
  require_db();
  const char *table = argv[0];
  if (!is_name(table)) die("nom de table invalide: %s", table);
  char *td = table_dir(table);
  if (exists_dir(td)) die("table deja existante: %s", table);
  mkdir_p(td);

  Schema s = {.pk_idx = -1};
  s.len = (size_t)argc - 1;
  s.cols = calloc(s.len, sizeof(Column));
  if (!s.cols && s.len) die("out of memory");
  int pk_count = 0;
  for (int i = 1; i < argc; i++) {
    char *spec = xstrdup(argv[i]);
    char *col = strtok(spec, ":"), *typ = strtok(NULL, ":"), *flag = strtok(NULL, ":");
    if (!col || !typ || !is_name(col)) die("spec colonne invalide: %s", argv[i]);
    if (strcmp(typ, "text") && strcmp(typ, "string") && strcmp(typ, "int") && strcmp(typ, "real") && strcmp(typ, "bool")) die("type invalide pour %s: %s", col, typ);
    if (flag && strcmp(flag, "pk") == 0) { pk_count++; s.pk_idx = i - 1; }
    else if (flag) die("option de colonne inconnue: %s", flag);
    if (pk_count > 1) die("une seule cle primaire est supportee");
    s.cols[i - 1].name = xstrdup(col);
    s.cols[i - 1].type = xstrdup(typ);
    s.cols[i - 1].pk = flag && strcmp(flag, "pk") == 0;
    free(spec);
  }
  RowSet empty = {0};
  write_schema(table, &s);
  write_rows(table, &s, &empty);
  free_schema(&s);
  free(td);
  printf("table creee: %s\n", table);
}

static void print_dump(const char *table, const char *where_col, const char *where_val) {
  Schema s = load_schema(table);
  RowSet rs = read_rows(table, &s);
  for (size_t i = 0; i < s.len; i++) { if (i) putchar('\t'); fputs(s.cols[i].name, stdout); }
  putchar('\n');
  for (size_t r = 0; r < rs.len; r++) {
    if (!row_matches(rs.rows[r], &s, where_col, where_val)) continue;
    for (size_t c = 0; c < s.len; c++) { if (c) putchar('\t'); fputs(rs.rows[r][c], stdout); }
    putchar('\n');
  }
  free_rowset(&rs, s.len);
  free_schema(&s);
}

static void cmd_select(int argc, char **argv) {
  if (argc != 1 && argc != 3) die("usage: bdb select TABLE [--where COL=VALUE]");
  require_db(); require_table(argv[0]);
  const char *where_col = NULL, *where_val = NULL;
  Assign where = {0};
  if (argc == 3) {
    if (strcmp(argv[1], "--where") != 0) die("clause attendue: --where COL=VALUE");
    where = parse_assign(argv[2]); where_col = where.col; where_val = where.val;
  }
  print_dump(argv[0], where_col, where_val);
  free(where.col); free(where.val);
}

static void cmd_insert(int argc, char **argv) {
  if (argc < 2) die("usage: bdb insert TABLE COL=VALUE...");
  require_db(); require_table(argv[0]);
  Schema s = load_schema(argv[0]);
  RowSet rs = read_rows(argv[0], &s);
  size_t an = (size_t)argc - 1;
  Assign *a = calloc(an, sizeof(Assign));
  if (!a) die("out of memory");
  for (size_t i = 0; i < an; i++) a[i] = parse_assign(argv[i + 1]);

  rs.rows = realloc(rs.rows, (rs.len + 1) * sizeof(char **));
  if (!rs.rows) die("out of memory");
  rs.rows[rs.len] = calloc(s.len, sizeof(char *));
  if (!rs.rows[rs.len]) die("out of memory");
  for (size_t c = 0; c < s.len; c++) {
    char *v = assignment_value(s.cols[c].name, a, an);
    if (!v) die("colonne manquante: %s", s.cols[c].name);
    if (!validate_type(s.cols[c].type, v)) die("valeur invalide pour %s (%s): %s", s.cols[c].name, s.cols[c].type, v);
    rs.rows[rs.len][c] = xstrdup(v);
  }
  rs.len++;
  write_rows(argv[0], &s, &rs);
  printf("ligne inseree: %s\n", argv[0]);
  free_assigns(a, an); free_rowset(&rs, s.len); free_schema(&s);
}

static void cmd_update(int argc, char **argv) {
  if (argc < 4 || strcmp(argv[1], "--where") != 0) die("usage: bdb update TABLE --where COL=VALUE COL=VALUE...");
  require_db(); require_table(argv[0]);
  Schema s = load_schema(argv[0]);
  RowSet rs = read_rows(argv[0], &s);
  Assign where = parse_assign(argv[2]);
  size_t an = (size_t)argc - 3, count = 0;
  Assign *a = calloc(an, sizeof(Assign));
  if (!a) die("out of memory");
  for (size_t i = 0; i < an; i++) a[i] = parse_assign(argv[i + 3]);
  for (size_t r = 0; r < rs.len; r++) {
    if (!row_matches(rs.rows[r], &s, where.col, where.val)) continue;
    count++;
    for (size_t c = 0; c < s.len; c++) {
      char *v = assignment_value(s.cols[c].name, a, an);
      if (!v) continue;
      if (!validate_type(s.cols[c].type, v)) die("valeur invalide pour %s (%s): %s", s.cols[c].name, s.cols[c].type, v);
      free(rs.rows[r][c]);
      rs.rows[r][c] = xstrdup(v);
    }
  }
  write_rows(argv[0], &s, &rs);
  printf("lignes modifiees: %zu\n", count);
  free_assigns(a, an); free(where.col); free(where.val); free_rowset(&rs, s.len); free_schema(&s);
}

static void cmd_delete(int argc, char **argv) {
  if (argc != 3 || strcmp(argv[1], "--where") != 0) die("usage: bdb delete TABLE --where COL=VALUE");
  require_db(); require_table(argv[0]);
  Schema s = load_schema(argv[0]);
  RowSet rs = read_rows(argv[0], &s), out = {0};
  Assign where = parse_assign(argv[2]);
  out.rows = calloc(rs.len, sizeof(char **));
  if (!out.rows && rs.len) die("out of memory");
  size_t count = 0;
  for (size_t r = 0; r < rs.len; r++) {
    if (row_matches(rs.rows[r], &s, where.col, where.val)) { count++; free_row(rs.rows[r], s.len); }
    else out.rows[out.len++] = rs.rows[r];
  }
  free(rs.rows);
  write_rows(argv[0], &s, &out);
  printf("lignes supprimees: %zu\n", count);
  free(where.col); free(where.val); free_rowset(&out, s.len); free_schema(&s);
}

static void cmd_drop(const char *table) {
  require_db(); require_table(table);
  char *td = table_dir(table), *schema = schema_path(table), *data = data_path(table);
  unlink(schema); unlink(data);
  if (rmdir(td) != 0) die("drop %s: %s", table, strerror(errno));
  printf("table supprimee: %s\n", table);
  free(schema); free(data); free(td);
}

static void usage(void) {
  puts("bdbc - moteur C natif pour bdb");
  puts("usage: bdb init|create|tables|schema|insert|select|dump|update|delete|drop ...");
}

int main(int argc, char **argv) {
  if (argc < 2) { usage(); return 0; }
  const char *cmd = argv[1];
  if (strcmp(cmd, "version") == 0 || strcmp(cmd, "--version") == 0) { puts(VERSION); return 0; }
  bool writes = !strcmp(cmd, "init") || !strcmp(cmd, "create") || !strcmp(cmd, "insert") || !strcmp(cmd, "update") || !strcmp(cmd, "delete") || !strcmp(cmd, "drop");
  if (writes) lock_db();
  if (strcmp(cmd, "init") == 0) cmd_init(argc - 2, argv + 2);
  else if (strcmp(cmd, "create") == 0) cmd_create(argc - 2, argv + 2);
  else if (strcmp(cmd, "tables") == 0) cmd_tables();
  else if (strcmp(cmd, "schema") == 0) { if (argc != 3) die("usage: bdb schema TABLE"); cmd_schema(argv[2]); }
  else if (strcmp(cmd, "select") == 0 || strcmp(cmd, "dump") == 0) {
    if (argc == 3 && strcmp(cmd, "dump") == 0) { require_db(); require_table(argv[2]); print_dump(argv[2], NULL, NULL); }
    else cmd_select(argc - 2, argv + 2);
  }
  else if (strcmp(cmd, "insert") == 0) cmd_insert(argc - 2, argv + 2);
  else if (strcmp(cmd, "update") == 0) cmd_update(argc - 2, argv + 2);
  else if (strcmp(cmd, "delete") == 0) cmd_delete(argc - 2, argv + 2);
  else if (strcmp(cmd, "drop") == 0) { if (argc != 3) die("usage: bdb drop TABLE"); cmd_drop(argv[2]); }
  else { usage(); if (writes) unlock_db(); return 64; }
  if (writes) unlock_db();
  return 0;
}
