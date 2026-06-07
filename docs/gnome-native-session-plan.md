# Session GNOME native pour Altitude

## Objectif

Remplacer le chemin historique Debian/LightDM par une session GNOME Wayland
entierement possedee par Altitude :

```text
minit
  -> udevd
  -> dbus system
  -> elogind
  -> services desktop systeme
  -> altitude-session-launch (root, PAM, tty2)
  -> dbus session (utilisateur minibash)
  -> gnome-session
  -> gnome-shell / Mutter (Wayland)
```

La cible ne contient ni LightDM, ni GDM, ni unite systemd, ni dependance au
demarrage Debian. `minit` reste le superviseur. Les paquets peuvent etre forges
sur un hote temporaire, mais chaque fichier livre doit appartenir a un paquet
Altitude construit depuis une source verrouillee.

## Decision structurante : la session doit passer par PAM

GNOME Shell ne doit pas etre lance par un simple `su`, `setpriv` ou
`chown /run/user/1000`. Ces operations changent l'identite Unix, mais ne creent
pas de session elogind. Mutter doit appartenir a une session active sur un VT
pour que `org.freedesktop.login1` lui accorde les descripteurs DRM et input.

Le lanceur natif sera donc un petit binaire Altitude,
`/usr/libexec/altitude-session-launch`, execute en root par le service
`gnome-native`. Il devra :

1. ouvrir `/dev/tty2`, en faire son terminal de controle et activer VT2 ;
2. appeler `pam_start("altitude-session", "minibash", ...)` ;
3. definir au minimum `PAM_TTY=tty2` et `PAM_RHOST` vide ;
4. appeler `pam_acct_mgmt`, `pam_setcred(PAM_ESTABLISH_CRED)` puis
   `pam_open_session` ;
5. lire l'environnement produit par PAM, notamment `XDG_SESSION_ID`,
   `XDG_SEAT`, `XDG_VTNR` et `XDG_RUNTIME_DIR` ;
6. initialiser les groupes, puis passer a l'UID/GID de `minibash` ;
7. lancer le bus de session et `gnome-session` ;
8. attendre toute la session, puis fermer proprement PAM avec
   `pam_close_session` et `pam_setcred(PAM_DELETE_CRED)`.

Le fichier `/etc/pam.d/altitude-session` est un profil d'autologin local de
confiance. Sa pile minimale doit inclure `pam_elogind.so` dans la phase
`session`. `pam_env.so` et `pam_limits.so` sont souhaitables. L'authentification
interactive reste hors du premier jalon ; le service choisit explicitement
l'utilisateur de bureau.

Le `/bin/login` Bash actuel ne convient pas a cette fonction : il authentifie
contre BDB, mais n'appelle pas PAM et ne change actuellement ni UID ni GID.
Une solution transitoire acceptable est le `login` PAM de util-linux sur VT2.
La cible finale reste le lanceur Altitude, afin de ne pas faire de util-linux
login le gestionnaire implicite de la session graphique.

## Ordre de demarrage sans systemd

### 1. Noyau, peripheriques et VT

`udevd` doit etre actif avant la session, puis effectuer un coldplug complet.
Les noeuds suivants sont des preconditions :

```text
/dev/tty2
/dev/dri/card*
/dev/dri/renderD*
/dev/input/event*
```

Le noyau doit fournir DRM/KMS, input, evdev, VT, namespaces, cgroups et
`CONFIG_DEVTMPFS`. Le service ne doit pas charger une liste de pilotes GPU
propre a une machine ; cette responsabilite appartient a `kmod` et udev.

### 2. Bus D-Bus systeme

Le service `dbus` possede exclusivement le bus systeme :

```sh
dbus-daemon --system --nofork --nopidfile
```

Avant son lancement, `/etc/machine-id` doit exister et etre stable. Le socket
`/run/dbus/system_bus_socket` constitue la condition de disponibilite. Le
lanceur GNOME ne doit pas demarrer un second bus de secours.

### 3. elogind

`elogind` est lance en premier plan par son service dedie apres D-Bus et udev.
La disponibilite reelle n'est pas seulement un PID : le nom
`org.freedesktop.login1` doit etre acquis sur le bus systeme.

`/run/systemd/seats`, `/run/systemd/sessions` et `/run/systemd/users` sont des
chemins d'API runtime utilises par elogind ; leur nom ne signifie pas que
systemd est PID 1. Ils doivent etre crees et geres par le paquet/service
elogind. Le lanceur GNOME ne doit pas effacer leur contenu pendant qu'elogind
tourne.

### 4. Services desktop systeme

Demarrer ensuite, chacun dans son service `minit`, les fournisseurs necessaires :

```text
polkitd            org.freedesktop.PolicyKit1
accounts-daemon    org.freedesktop.Accounts
upowerd            org.freedesktop.UPower
rtkit-daemon       org.freedesktop.RealtimeKit1
udisksd            org.freedesktop.UDisks2
NetworkManager     org.freedesktop.NetworkManager   (si retenu)
```

Polkit est requis pour un bureau administrable. AccountsService, UPower,
RealtimeKit, UDisks2 et NetworkManager peuvent etre introduits par jalons, mais
leurs absences doivent etre explicites dans les tests et non masquees par des
fallbacks lances depuis le service GNOME.

### 5. Session utilisateur et bus de session

Apres `pam_open_session`, elogind doit avoir cree `/run/user/1000` avec le mode
`0700` et le proprietaire `minibash`. Le lanceur ne doit pas fabriquer ce
repertoire avant PAM, sauf eventuel nettoyage d'un boot precedent avant le
demarrage d'elogind.

Le premier jalon utilise D-Bus classique :

```sh
dbus-run-session -- gnome-session --session=gnome
```

`dbus-run-session` est execute apres le changement d'identite. Le bus utilisateur
doit donc publier `DBUS_SESSION_BUS_ADDRESS` dans l'environnement de toute la
session. `dbus-broker` pourra remplacer ce chemin plus tard, apres definition
d'un lanceur non-systemd explicite.

Environnement initial :

```text
HOME=/home/minibash
USER=minibash
LOGNAME=minibash
SHELL=/bin/bash
XDG_RUNTIME_DIR=/run/user/1000
XDG_SESSION_TYPE=wayland
XDG_SESSION_CLASS=user
XDG_SESSION_DESKTOP=gnome
XDG_CURRENT_DESKTOP=GNOME
XDG_CONFIG_DIRS=/etc/xdg
XDG_DATA_DIRS=/usr/local/share:/usr/share
```

Ne pas forcer `DISPLAY`, `WAYLAND_DISPLAY`, `GDK_BACKEND`,
`LIBGL_ALWAYS_SOFTWARE` ou `XAUTHORITY`. GNOME/Mutter doit creer son socket
Wayland et choisir le rendu. Xwayland publiera `DISPLAY` lui-meme lorsqu'il est
disponible.

La commande de production est `gnome-session --session=gnome`, pas
`gnome-shell` seul. Le lancement direct de `gnome-shell --wayland` est reserve
au diagnostic de Mutter et ne fournit pas le cycle de vie complet de la
session GNOME.

## Contrat du futur service `gnome-native`

Le script shell, lorsqu'il sera cable, devra rester un superviseur mince :

1. verifier les binaires et les devices requis ;
2. attendre le socket D-Bus systeme et `org.freedesktop.login1` avec un delai
   borne ;
3. verifier que `seat0` et `tty2` sont visibles via login1 ;
4. executer `altitude-session-launch --user minibash --tty /dev/tty2` au
   premier plan ;
5. propager `TERM`, `INT` et `HUP` au lanceur ;
6. journaliser dans `/var/log/gnome-native.log` ;
7. sortir en erreur si la session se termine, pour laisser la politique de
   redemarrage a `minit`.

Il ne devra ni demarrer D-Bus/elogind/polkit, ni tuer globalement tous les
processus GNOME, ni reecrire le home utilisateur, ni creer des fichiers
`.xsession`. Le nettoyage doit suivre l'arbre de processus et la session PAM.

Dependances BDB cibles, a integrer par le proprietaire de la configuration :

```text
gnome-native after udevd
gnome-native requires dbus
gnome-native requires elogind
gnome-native requires polkit
```

`displayd`, concu autour de X11/LightDM et de son `XAUTHORITY`, ne fait pas
partie du chemin Wayland natif.

## Paquets Altitude requis

La liste distingue le socle deja amorce dans les recettes du depot et la
fermeture runtime encore a empaqueter. Chaque bibliotheque chargee par
`dlopen`, chaque fichier D-Bus, schema GSettings, session desktop, plugin ou
driver doit figurer dans les manifestes ; une verification par `ldd` seule est
insuffisante.

### Socle deja amorce

```text
altitude-glibc / toolchain runtime
altitude-bash, altitude-busybox
altitude-libffi, altitude-pcre2, altitude-expat
altitude-glib, altitude-dbus
altitude-wayland, altitude-wayland-protocols
altitude-libdrm, altitude-mesa
altitude-libpng, altitude-freetype, altitude-fontconfig
altitude-pixman, altitude-cairo, altitude-harfbuzz, altitude-pango
altitude-gtk4
```

### Assise systeme obligatoire

```text
linux-pam
elogind, libelogind, pam_elogind
udev/eudev et libudev
libcap, libseccomp
libinput, libevdev, mtdev
libxkbcommon, xkeyboard-config
polkit
shadow ou une implementation Altitude de initgroups/getpwnam compatible NSS
altitude-session-launcher
```

Le compte `minibash` doit exister dans les interfaces libc attendues par PAM et
GNOME (`getpwnam`, `getgrouplist`, groupes supplementaires). La seule table BDB
ne suffit pas tant qu'un module NSS Altitude ou une synchronisation vers
`/etc/passwd` et `/etc/group` n'est pas fourni.

### Runtime GNOME minimal

```text
gsettings-desktop-schemas
dconf
gdk-pixbuf
graphene
libepoxy
librsvg
mozjs
gjs
gnome-desktop
mutter
gnome-shell
gnome-session
gnome-settings-daemon
adwaita-icon-theme
gnome-backgrounds
cantarell-fonts
shared-mime-info
desktop-file-utils
```

Les versions de `mutter`, `gnome-shell`, `gnome-session`, `gjs`, `mozjs` et des
schemas doivent provenir d'une meme serie GNOME testee. Elles ne doivent pas
etre mises a jour independamment sur l'image.

### Integration d'un bureau complet

```text
accountsservice
upower
rtkit
udisks2
NetworkManager
PipeWire, WirePlumber
GStreamer et plugins requis
xdg-desktop-portal, xdg-desktop-portal-gnome
Xwayland
gnome-control-center
gnome-terminal ou console
nautilus
```

PipeWire/WirePlumber deviennent obligatoires avant de declarer audio,
partage/capture d'ecran et portail RemoteDesktop fonctionnels. Xwayland est
requis pour les applications X11, mais pas pour prouver le premier affichage
Wayland natif.

### Fichiers runtime a ne pas oublier

```text
/usr/share/gnome-session/sessions/gnome.session
/usr/share/wayland-sessions/gnome.desktop
/usr/share/applications/*.desktop
/usr/share/dbus-1/system-services/*
/usr/share/dbus-1/services/*
/usr/share/glib-2.0/schemas/* + gschemas.compiled
/usr/share/icons/Adwaita/*
/usr/share/fonts/*
/usr/lib*/girepository-1.0/*
/usr/lib*/gnome-shell/*
/usr/lib*/mutter-*
/etc/pam.d/altitude-session
/etc/dbus-1/system.d/* ou /usr/share/dbus-1/system.d/*
```

## Plan de migration

1. Fermer le socle udev, PAM, elogind et NSS dans des paquets Altitude.
2. Ecrire et tester `altitude-session-launch` sans GNOME, avec une commande
   utilisateur longue qui permet de verifier la session login1 sur VT2.
3. Empaqueter Mutter et sa fermeture runtime ; valider un lancement Wayland
   direct uniquement comme test de compositing.
4. Empaqueter `gnome-session`, `gnome-shell` et les schemas d'une meme serie ;
   lancer la session via le bus D-Bus utilisateur.
5. Ajouter `gnome-native.sh`, puis faire integrer ses dependances BDB sans
   modifier l'ancien service pendant la phase de comparaison.
6. Ajouter les services d'integration et les portails un par un.
7. Basculer le service graphique configure vers `gnome-native`.
8. Supprimer LightDM, ses fichiers PAM/configuration, les artefacts `.xsession`
   et les paquets Debian de l'image seulement apres validation sur machine
   reelle et en VM.

## Validation

Avant GNOME :

```sh
busctl --system list | grep org.freedesktop.login1
loginctl seat-status seat0
loginctl session-status
stat -c '%U %G %a' /run/user/1000
```

Pendant la session, `loginctl session-status` doit montrer `minibash`, `seat0`,
`tty2`, `Type=wayland`, une session active et `gnome-session` dans son arbre de
processus. Les tests d'acceptation sont :

1. GNOME apparait sur VT2 sans LightDM/GDM et sans processus systemd ;
2. clavier, souris et rendu GPU fonctionnent sans groupes `video/input`
   utilises comme contournement de logind ;
3. `busctl --user` fonctionne depuis un terminal GNOME ;
4. verrouillage/deverrouillage et changement de VT conservent la mediation
   elogind ;
5. l'arret du service ferme la session PAM, libere DRM/input et revient sur
   VT1 ;
6. un crash de GNOME ne laisse ni bus utilisateur ni session login1 orpheline ;
7. le boot console reste utilisable lorsque le paquet GNOME est absent.

Le jalon est termine lorsque ces controles passent avec une image reconstruite
uniquement depuis les paquets Altitude et que `lightdm`, `gdm`, `apt`, `dpkg`
et leurs bases runtime sont absents de cette image.
