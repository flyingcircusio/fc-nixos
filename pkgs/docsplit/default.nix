{ lib
, bundlerApp
, ruby
, libreoffice
, file
, graphicsmagick
, poppler_utils
, pdftk
, jre
, makeWrapper
, ... }:

bundlerApp {
  pname = "docsplit";
  ruby = ruby;
  gemdir = ./.;
  exes = [ "docsplit" ];
  postBuild = ''
    # this is somewhat of a hack as bundlerApp defines its own set of wrappers
    source ${makeWrapper}/nix-support/setup-hook

    wrapProgram $out/bin/docsplit \
      --set OFFICE_PATH ${libreoffice}/bin \
      --prefix PATH : ${lib.makeBinPath
        [ file graphicsmagick poppler_utils pdftk jre ] }
  '';

  meta = with lib; {
    description = ''
      A command-line utility and Ruby library for splitting apart documents
      into their component parts
    '';
    homepage    = https://documentcloud.github.io/docsplit/;
    license     = licenses.lgpl2;
    maintainers = with maintainers; [ zagy ];
    platforms   = platforms.unix;
  };
}
