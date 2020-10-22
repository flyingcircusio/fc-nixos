{ stdenv, fetchFromGitHub, qt4, fontconfig, freetype, libpng, zlib, libjpeg
, openssl, libX11, libXext, libXrender, lib }:

# wkhtmltopdf is a weird beast.
#
# Most of the functionality is derived from an older QT version providing
# webkit applied with a bunch of fixes that never made it upstream.
#
# See https://wkhtmltopdf.org/status.html for details and whether things have
# changed.
#
# For the 0.12 release series we came to the conclusion that we simply have to
# use the patched QT version - otherwise weird output bugs will creep in.
#
# NixOS already provides a patched built of QT 4, some of which are already
# applied in the patched QT version from wkhtmltopdf, so we deselect those.
#
# Previously (before this solution here) we thought that individual versions
# of wkhtmltopdf like 0.12.3, 0.12.4, 0.12.5 had different bugs that users
# were experiencing, but the "patched QT" fix seems to have shown us that
# NixOS (and our own builds) didn't properly include the patched QT version
# all the time.
#
# As a history of this code, here are the bugs we had in our hands:
#
# * #128175 triggered a full review of this code and has shown us that
#   we maybe do not need pin the versions but need to be careful about
#   including the right version of QT.
#

let
  wkQt = qt4.overrideAttrs (oldAttrs: rec {
    name = "qt-mod-4.8.7-5db36ec";
    enableParallelBuilding = true;
    src = fetchFromGitHub {
      owner  = "wkhtmltopdf";
      repo   = "qt";
      # This needs to be the exact revision that wkhtmltopdf revers to in its
      # git submodule matching the release tag of wkhtmltopdf
      rev    = "5db36ec76b29712eb2c5bd0625c2c77d7468b3fc";
      sha256 = "1jnzh9pvdfsyg1whh66i4bc58b88rswln2vvcbvx8jd33zbisscr";
    };
    # The QT version maintained by wkhtmltopdf already includes a number of
    # the NixOS QT4 patches, so those need to be filtered out.
    excludePatches = [
      "clang-5-darwin.patch"
      "libressl.patch"
      "qt4-openssl-1.1.patch"
      "qt4-gcc6.patch"
    ];
    patches = [ ./qt4-gcc9.patch ] ++ builtins.filter (
      patch: ! lib.any (exclude: builtins.baseNameOf patch == exclude)
                       excludePatches ) oldAttrs.patches;
    configureFlags =
      ''
        -dbus-linked
        -glib
        -no-separate-debug-info
        -openssl-linked
        -qdbus
        -v
      ''
      + # This is taken from the wkhtml build script that we don't run
      ''
        -confirm-license
        -exceptions
        -fast
        -graphicssystem raster
        -iconv
        -largefile
        -no-3dnow
        -no-accessibility
        -no-audio-backend
        -no-avx
        -no-cups
        -no-dbus
        -no-declarative
        -no-glib
        -no-gstreamer
        -no-gtkstyle
        -no-icu
        -no-javascript-jit
        -no-libmng
        -no-libtiff
        -nomake demos
        -nomake docs
        -nomake examples
        -nomake tests
        -nomake tools
        -nomake translations
        -no-mitshm
        -no-mmx
        -no-multimedia
        -no-nas-sound
        -no-neon
        -no-nis
        -no-opengl
        -no-openvg
        -no-pch
        -no-phonon
        -no-phonon-backend
        -no-qt3support
        -no-rpath
        -no-scripttools
        -no-sm
        -no-sql-ibase
        -no-sql-mysql
        -no-sql-odbc
        -no-sql-psql
        -no-sql-sqlite
        -no-sql-sqlite2
        -no-sse
        -no-sse2
        -no-sse3
        -no-sse4.1
        -no-sse4.2
        -no-ssse3
        -no-stl
        -no-xcursor
        -no-xfixes
        -no-xinerama
        -no-xinput
        -no-xkb
        -no-xrandr
        -no-xshape
        -no-xsync
        -opensource
        -release
        -static
        -system-libjpeg
        -system-libpng
        -system-zlib
        -webkit
        -xmlpatterns
      '';
  });
in

stdenv.mkDerivation rec {
  version = "0.12.5";
  name = "wkhtmltopdf-${version}";

  src = fetchFromGitHub {
    owner  = "wkhtmltopdf";
    repo   = "wkhtmltopdf";
    rev    = version;
    sha256 = "0i6b6z3f4szspbbi23qr3hv22j9bhmcj7c1jizr7y0ra43mrgws1";
  };

  buildInputs = [
    wkQt fontconfig freetype libpng zlib libjpeg openssl
    libX11 libXext libXrender
  ];

  prePatch = ''
    for f in src/image/image.pro src/pdf/pdf.pro ; do
      substituteInPlace $f --replace '$(INSTALL_ROOT)' ""
    done
  '';

  configurePhase = "qmake wkhtmltopdf.pro INSTALLBASE=$out";

  enableParallelBuilding = true;

  meta = with stdenv.lib; {
    homepage = https://wkhtmltopdf.org/;
    description = "Tools for rendering web pages to PDF or images";
    longDescription = ''
      wkhtmltopdf and wkhtmltoimage are open source (LGPL) command line tools
      to render HTML into PDF and various image formats using the QT Webkit
      rendering engine. These run entirely "headless" and do not require a
      display or display service.
      There is also a C library, if you're into that kind of thing.
    '';
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [ jb55 ];
    platforms = with platforms; linux;
  };
}
