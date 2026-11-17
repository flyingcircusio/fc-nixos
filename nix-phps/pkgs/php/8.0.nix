{
  prev,
  mkPhp,
}:

let
  base = mkPhp {
    version = "8.0.30";
    hash = "sha256-mKnLag4nppUM30sm3KxI8r4tk21SJKUC8GbPPUzxm5I=";
    extraPatches = [
      (prev.fetchpatch {
        url = "https://github.com/php/php-src/commit/82f8f31b16a035c1b67cc253e79f7cc288f4cc20.patch";
        hash = "sha256-AcxKFJ1pGrTgxvsBu2kXTDAIBMXdRbnQpiG2O8xmxxk=";
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
  ([
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
    imap
    intl
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
  ])
)
