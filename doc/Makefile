.PHONY: all html clean

all: gen-platform-versions checkout-versioned-docs html

gen-platform-versions: 
	./appenv python -m tools.gen_platform_versions

checkout-versioned-docs: 
	./appenv python -m tools.checkout_versioned_docs

html:
	./zensical build

clean:
	rm -rf _build
