import argparse
import glob

ACTION_ENABLE = "enable"
ACTION_DISABLE = "disable"
ACTION_STATUS = "status"


class Slot(object):
    def __init__(self, device):
        self.device = device

        for candidate in glob.glob(
            "/sys/class/enclosure/*/Slot*/device/block/*"
        ):
            _, _, _, _, enclosure, slot, _, _, device = candidate.split("/")
            if self.device == device:
                self.enclosure = enclosure
                self.slot = slot
                break
        else:
            raise KeyError(
                f"Could not find enclosure slot for device {self.device}"
            )

    @property
    def locate_path(self):
        return f"/sys/class/enclosure/{self.enclosure}/{self.slot}/locate"

    @property
    def locate_led(self):
        with open(self.locate_path) as f:
            return bool(int(f.read().strip()))

    @locate_led.setter
    def locate_led(self, status):
        with open(self.locate_path, "w") as f:
            return f.write(str(int(bool(status))))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("device")
    parser.add_argument(
        "action",
        default=ACTION_STATUS,
        choices=[ACTION_STATUS, ACTION_ENABLE, ACTION_DISABLE],
    )
    args = parser.parse_args()

    slot = Slot(args.device)

    if args.action == ACTION_ENABLE:
        slot.locate_led = True
    elif args.action == ACTION_DISABLE:
        slot.locate_led = False

    print(f"Device {slot.device} is located in {slot.enclosure}/{slot.slot}.")
    print(f"  Locate LED enabled: {slot.locate_led}")


if __name__ == "__main__":
    main()
