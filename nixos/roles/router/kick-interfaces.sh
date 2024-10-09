kick_interface() {
    local int=$1

    for x in $(ip l show dev "$int" | grep 'DOWN' | cut -d ':' -f 2); do
        echo "Kicking ${x}"
        ethtool -r "$x"
        sleep 5
        ethtool "$x"
    done
}

for x in "$@"; do
    echo "Checking $x"
    kick_interface "$x";
done
