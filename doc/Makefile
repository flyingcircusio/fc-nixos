.PHONY: all html html-en html-de clean

all: html

html: html-en html-de

html-en:
	./zensical build

html-de:
	./appenv python scripts/derive_src_de.py
	./zensical build -f zensical-de.toml

clean:
	rm -rf _build src-de
