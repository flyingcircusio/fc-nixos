{
  prev,
  mkPhp,
}:

let
  base = mkPhp {
    version = "7.4.33";
    hash = "sha256-ToEXRY/lpHW/IDEocmtxvLumHEKtRj3/re5WZ6GYqYo=";
    extraPatches = [
      (prev.fetchpatch {
        url = "https://github.com/php/php-src/commit/712e60f9edfd03f0960fc4fc3c2c375f42b90aa2.patch";
        hash = "sha256-hBrt0QH0j6iDQmylpt3Rj//F8266gUeRyHDwxE3DR2A=";
      })
    ];
  };
in
base.withExtensions (
  {
    all,
    ...
  }:

  with all;
  (
    [
      bcmath
      calendar
      curl
      ctype
      dom
      exif
      fileinfo
      filter
      ftp
      gd
      gettext
      gmp
      iconv
      intl
      json
      ldap
      mbstring
      mysqli
      mysqlnd
      opcache
      openssl
      pcntl
      pdo
      pdo_mysql
      pdo_odbc
      pdo_pgsql
      pdo_sqlite
      pgsql
      posix
      readline
      session
      simplexml
      sockets
      soap
      sodium
      sysvsem
      sqlite3
      tokenizer
      xmlreader
      xmlwriter
      zip
      zlib
    ]
    ++ prev.lib.optionals (!prev.stdenv.isDarwin) [
      imap
    ]
  )
)
