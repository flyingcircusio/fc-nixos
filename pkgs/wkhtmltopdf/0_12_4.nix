{ stdenv, lib, fetchFromGitHub, fetchpatch, qt4, fontconfig, freetype, libpng
, zlib, libjpeg, openssl, libX11, libXext, libXrender }:

stdenv.mkDerivation rec {
  version = "0.12.4";
  name = "wkhtmltopdf-${version}";

  src = fetchFromGitHub {
    owner  = "wkhtmltopdf";
    repo   = "wkhtmltopdf";
    rev    = version;
    sha256 = "09yzj9ylc6ci4a1qlhz60cgxi1nm9afwjrjxfikf8wwjd3i24vp2";
  };

  wkQt = qt4.overrideAttrs (deriv: {
    name = "qt-mod-4.8.7";
    enableParallelBuilding = true;
    src = fetchFromGitHub {
      owner  = "wkhtmltopdf";
      repo   = "qt";
      rev    = "fe194f9dac0b515757392a18f7fc9527c91d45ab"; # From git submodule spec in wkhtml repo.
      sha256 = "1j2ld2bfacnn3vm2l1870v55sj82bq4y8zkawmlx2y5j63d8vr23";
    };
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
        -opensource
        -fast
        -release
        -static
        -graphicssystem raster
        -webkit
        -exceptions
        -xmlpatterns
        -system-libjpeg
        -system-libpng
        -system-zlib
        -no-libmng
        -no-libtiff
        -no-accessibility
        -no-stl
        -no-qt3support
        -no-phonon
        -no-phonon-backend
        -no-opengl
        -no-declarative
        -no-scripttools
        -no-sql-db2
        -no-sql-ibase
        -no-sql-mysql
        -no-sql-oci
        -no-sql-odbc
        -no-sql-psql
        -no-sql-sqlite
        -no-sql-sqlite2
        -no-sql-tds
        -no-mmx
        -no-3dnow
        -no-sse
        -no-sse2
        -no-multimedia
        -nomake demos
        -nomake docs
        -nomake examples
        -nomake tests
        -nomake tools
        -nomake translations
      '';
  });

  buildInputs = [
    wkQt fontconfig freetype libpng zlib libjpeg openssl
    libX11 libXext libXrender
  ];

  prePatch = ''
    for f in src/image/image.pro src/pdf/pdf.pro ; do
      substituteInPlace $f --replace '$(INSTALL_ROOT)' ""
    done
  '';

  patches = [
    (fetchpatch {
      name = "make-0.12.4-compile.patch";
      url = "https://github.com/efx/aports/raw/eb9f8e6bb9a488460929db747b15b8fceddd7abd/testing/wkhtmltopdf/10-patch1.patch";
      sha256 = "1c136jz0klr2rmhmy13gdbgsgkpjfdp2sif8bnw8d23mr9pym3s1";
    })
  ];

  configurePhase = "qmake wkhtmltopdf.pro INSTALLBASE=$out";

  enableParallelBuilding = true;

  meta = with lib; {
    homepage = http://wkhtmltopdf.org/;
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
