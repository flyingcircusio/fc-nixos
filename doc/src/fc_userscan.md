(nixos-fc-userscan)=

# fc-userscan

Protects installed packages that might still be needed from garbage collection.

## Rationale

Like on every other Linux distribution, you may install some arbitrary library
via the package manager, manually compile a program against it and as long as
this library exists, there is no problem.

With Nix, smallest changes somewhere down the dependency chain will change
hashes from which Nix store paths are constructed. That means that references
to Nix store paths may become outdated quickly. Nix automatically rebuilds
Nix packages to reflect the dependency changes. Things installed outside of
the Nix store, for example a Python virtualenv in a service user home
directory have to be updated manually. As long as the outdated Nix store path
is available, everything still works. But, as Nix normally wouldn't know
about this external use of the store path, the Nix store garbage collection
will remove the old version if it's not referenced in the Nix store or by a
explicitly added "gcroot". This means that your application now
cannot find some dependency anymore and stops working.

To avoid that, [fc-userscan]
(https://github.com/flyingcircusio/userscan) searches for references to Nix
store paths in home directories and ensures that these packages
are not garbage collected by creating "gcroots" for the files that reference
these packages.

## Periodic and manual garbage collection

Our daily platform task `fc-collect-garbage.timer` runs `fc-userscan` first to
search all home directories of human and service users to protect them in the
following garbage collection step. You can also run
{cmd}`sudo fc-collect-garbage` (available for service and sudo-srv users) to
trigger the process.

## Files and directories excluded from scanning

Keeping all packages that are references somewhere brings a new problem. For
example a logfile may refer to an old and unneeded Nix package and as long as
the log exists the old package would not be deleted and the nix store grows
in size.

There's a default set of excludes in {file}`/etc/userscan/exclude` which is
used by {cmd}`fc-collect-garbage` automatically.

If you need to add more exclusion rules you may add them as one regex per line
to `~/.userscan-ignore`. This uses the same pattern format as [gitignore]
(https://git-scm.com/docs/gitignore). The home folder in this case is the
home folder of the service user.

Note that paths to a subdirectory, like `.cache/test/somefile` don't match
anything unless prefixed with `**/` which means that the path is matched
everywhere, for example at `/home/test/sub/dir/.cache/test/somefile`. There's
no way to reference sub directories of the home directory directly at the
moment. We will fix that in the future.

Currently, the following paths are ignored:

~~~
# Directories to ignore (anywhere in the home directory)
**/.cache/nix/
**/.git/objects/
**/.gnupg/
**/.hg/store/
**/.nix-defexpr/
**/elasticsearch/data/
**/graylog/data/
**/influxdb/data/
**/journal/
**/lucene/
**/solr/data/
# Files in sub-directories to ignore (anywhere in the home directory)
**/.local/share/fish/fish_history
**/diagnostic.data/metrics.*
**/mongodb/*.wt
**/mysql/*/*.{MYD,MYI,frm,ibd}
**/mysql/ib*
**/postgresql/*/base
**/postgresql/*/pg_*
**/redis/*.rdb
# File extensions to ignore
*.JPG
*.bak
*.bmp
*.bz2
*.crt
*.css
*.deb
*.diff
*.doc
*.docx
*.eml
*.flac
*.gif
*.gz
*.htm
*.html
*.icc
*.jar
*.jpeg
*.jpg
*.json
*.kml
*.kmz
*.lock
*.log
*.log-????????
*.log.?
*.lzh
*.m4a
*.md
*.mid
*.mp3
*.mp4
*.ods
*.odt
*.ogg
*.otf
*.patch
*.pcl
*.pdf
*.pdf
*.pid
*.pki
*.png
*.ppt
*.pptx
*.psd
*.psd
*.rar
*.rpm
*.rss
*.sock
*.socket
*.spl
*.sql
*.svg
*.tgz
*.tif
*.tiff
*.ttf
*.vcl
*.war
*.wav
*.webm
*.xlf
*.xls
*.xlsx
*.xml
*.xz
*.zdsock
*.zopectlsock
*~
# Cache, history and data files to ignore
.bash_history
.viminfo
.z
.zsh_history
Data.fs
Data.fs.tmp
GeoLite2-City.mmdb
fc-userscan.cache
zeoclient_*.zec
~~~
