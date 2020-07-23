source $stdenv/setup

echo "unpacking $src..."
tar xvfa $src
p=$out/lib/php/extensions/
mkdir -p $p

cp tideways-*/*.so $p
