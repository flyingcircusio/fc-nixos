from fc.maintenance.activity import Activity, ActivityMergeResult
from fc.maintenance.estimate import Estimate


class MergeableActivity(Activity):
    estimate = Estimate("10")

    def __init__(self, value="test", significant=True):
        super().__init__()
        self.value = value
        self.significant = significant

    @property
    def comment(self):
        return self.value

    def merge(self, other):
        if not isinstance(other, MergeableActivity):
            return ActivityMergeResult()

        # Simulate merging an activity that reverts this activity, resulting
        # in a no-op situation.
        if other.value == "inverse":
            return ActivityMergeResult(self, is_effective=False)

        self.value = other.value
        return ActivityMergeResult(
            self, is_effective=True, is_significant=self.significant
        )
