#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ALTITUDE_RECIPE_OUT:-$ROOT/out/source-packages}"
WORK="${ALTITUDE_RECIPE_WORK:-$ROOT/out/source-work/appstream}"
VERSION=1.0.6
TARGET="${ALTITUDE_TARGET_TRIPLET:-x86_64-altitude-linux-gnu}"
TOOLCHAIN_ROOT="${ALTITUDE_TOOLCHAIN_ROOT:-}"
FORGE_ROOT="${ALTITUDE_FORGE_ROOT:-}"
TOOLCHAIN="$TOOLCHAIN_ROOT/opt/altitude/toolchain"
FORGE="$FORGE_ROOT/opt/altitude/forge"
SYSROOT="$TOOLCHAIN/sysroot"
CC="$TOOLCHAIN/bin/$TARGET-gcc"
STRIP="$TOOLCHAIN/bin/$TARGET-strip"
PKG_CONFIG="$FORGE/bin/pkg-config"
PAYLOAD="$WORK/payload"

export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

[ -x "$CC" ] || { echo "appstream: missing compiler: $CC" >&2; exit 1; }
[ -x "$PKG_CONFIG" ] || { echo "appstream: missing pkg-config: $PKG_CONFIG" >&2; exit 1; }
"$PKG_CONFIG" --exists glib-2.0 gobject-2.0 ||
  { echo "appstream: missing glib/gobject in $SYSROOT" >&2; exit 1; }

rm -rf "$WORK"
mkdir -p "$WORK" "$PAYLOAD/usr/include" "$PAYLOAD/usr/lib/pkgconfig" \
  "$PAYLOAD/usr/share/altitude/sources" "$OUT"

cat > "$WORK/appstream.h" <<'EOF'
#pragma once

#include <gio/gio.h>

G_BEGIN_DECLS

typedef GObject AsMetadata;
typedef GObject AsComponent;
typedef GObject AsLaunchable;
typedef GObject AsRelease;
typedef GObject AsDeveloper;
typedef GPtrArray AsReleaseList;

typedef enum {
  AS_FORMAT_KIND_UNKNOWN = 0
} AsFormatKind;

typedef enum {
  AS_LAUNCHABLE_KIND_DESKTOP_ID = 1
} AsLaunchableKind;

typedef enum {
  AS_URL_KIND_HOMEPAGE = 0,
  AS_URL_KIND_BUGTRACKER = 1,
  AS_URL_KIND_HELP = 2
} AsUrlKind;

#define AS_MAJOR_VERSION 1
#define AS_MINOR_VERSION 0
#define AS_MICRO_VERSION 6
#define AS_CHECK_VERSION(major,minor,micro) \
  (AS_MAJOR_VERSION > (major) || \
   (AS_MAJOR_VERSION == (major) && AS_MINOR_VERSION > (minor)) || \
   (AS_MAJOR_VERSION == (major) && AS_MINOR_VERSION == (minor) && AS_MICRO_VERSION >= (micro)))

AsMetadata *as_metadata_new (void);
gboolean as_metadata_parse_file (AsMetadata *metadata, GFile *file,
                                 AsFormatKind format, GError **error);
AsComponent *as_metadata_get_component (AsMetadata *metadata);
const gchar *as_component_get_id (AsComponent *component);
AsLaunchable *as_component_get_launchable (AsComponent *component,
                                           AsLaunchableKind kind);
GPtrArray *as_launchable_get_entries (AsLaunchable *launchable);
GPtrArray *as_component_get_releases (AsComponent *component);
AsReleaseList *as_component_get_releases_plain (AsComponent *component);
GPtrArray *as_release_list_get_entries (AsReleaseList *list);
const gchar *as_release_get_description (AsRelease *release);
const gchar *as_release_get_version (AsRelease *release);
const gchar *as_component_get_name (AsComponent *component);
const gchar *as_component_get_project_license (AsComponent *component);
const gchar *as_component_get_url (AsComponent *component, AsUrlKind kind);
AsDeveloper *as_component_get_developer (AsComponent *component);
const gchar *as_developer_get_name (AsDeveloper *developer);
const gchar *as_component_get_developer_name (AsComponent *component);

G_DEFINE_AUTOPTR_CLEANUP_FUNC (AsMetadata, g_object_unref)

G_END_DECLS
EOF

cat > "$WORK/appstream.c" <<'EOF'
#include "appstream.h"

AsMetadata *
as_metadata_new (void)
{
  return g_object_new (G_TYPE_OBJECT, NULL);
}

gboolean
as_metadata_parse_file (AsMetadata *metadata, GFile *file,
                        AsFormatKind format, GError **error)
{
  g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_NOT_SUPPORTED,
                       "Altitude AppStream metadata parsing is not available");
  return FALSE;
}

AsComponent *as_metadata_get_component (AsMetadata *metadata) { return NULL; }
const gchar *as_component_get_id (AsComponent *component) { return NULL; }
AsLaunchable *as_component_get_launchable (AsComponent *component, AsLaunchableKind kind) { return NULL; }
GPtrArray *as_launchable_get_entries (AsLaunchable *launchable) { return NULL; }
GPtrArray *as_component_get_releases (AsComponent *component) { return NULL; }
AsReleaseList *as_component_get_releases_plain (AsComponent *component) { return NULL; }
GPtrArray *as_release_list_get_entries (AsReleaseList *list) { return NULL; }
const gchar *as_release_get_description (AsRelease *release) { return NULL; }
const gchar *as_release_get_version (AsRelease *release) { return NULL; }
const gchar *as_component_get_name (AsComponent *component) { return NULL; }
const gchar *as_component_get_project_license (AsComponent *component) { return NULL; }
const gchar *as_component_get_url (AsComponent *component, AsUrlKind kind) { return NULL; }
AsDeveloper *as_component_get_developer (AsComponent *component) { return NULL; }
const gchar *as_developer_get_name (AsDeveloper *developer) { return NULL; }
const gchar *as_component_get_developer_name (AsComponent *component) { return NULL; }
EOF

cflags="$("$PKG_CONFIG" --cflags glib-2.0 gobject-2.0 gio-2.0)"
libs="$("$PKG_CONFIG" --libs glib-2.0 gobject-2.0 gio-2.0)"
"$CC" -O2 -fPIC -shared $cflags -o "$PAYLOAD/usr/lib/libappstream.so.5.0.0" \
  "$WORK/appstream.c" $libs -Wl,-soname,libappstream.so.5
ln -s libappstream.so.5.0.0 "$PAYLOAD/usr/lib/libappstream.so.5"
ln -s libappstream.so.5 "$PAYLOAD/usr/lib/libappstream.so"
install -m644 "$WORK/appstream.h" "$PAYLOAD/usr/include/appstream.h"

cat > "$PAYLOAD/usr/lib/pkgconfig/appstream.pc" <<EOF
prefix=/usr
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: AppStream
Description: Minimal Altitude AppStream compatibility shim
Version: $VERSION
Requires: glib-2.0 gobject-2.0 gio-2.0
Libs: -L\${libdir} -lappstream
Cflags: -I\${includedir}
EOF

"$STRIP" --strip-unneeded "$PAYLOAD/usr/lib/libappstream.so.5.0.0" 2>/dev/null || true

install -d "$SYSROOT/usr"
cp -a "$PAYLOAD/usr/." "$SYSROOT/usr/"

{
  echo "Source: Altitude Linux"
  echo "Version: $VERSION"
  echo "Build: minimal AppStream ABI shim for libadwaita"
  echo "Upstream-note: replace with full AppStream when metadata catalogs are enabled"
  echo "Compiler: $("$CC" --version | head -1)"
} > "$PAYLOAD/usr/share/altitude/sources/appstream.build"

bash "$ROOT/rootfs/bin/altpkg-build" \
  "$ROOT/recipes/appstream/MANIFEST" "$PAYLOAD" \
  "$OUT/altitude-appstream-$VERSION-amd64.altpkg"
