from fc.maintenance import Request
from fc.maintenance.activity import RebootType

SERIALIZED_REQUEST = """
!!python/object:fc.maintenance.request.Request
_comment: null
_estimate: null
_reqid: RqZnZSVRD6d3ojcmhpaCmv
_reqmanager: null
activity: !!python/object:fc.maintenance.lib.reboot.RebootActivity
  action: reboot
  coldboot: true
  initial_boottime: 1695578792.5227735
added_at: 2023-09-29 22:23:34.623081+00:00
attempts: []
comment: Reboot to activate changed kernel (5.15.119 to 6.1.51)
dir: /var/spool/maintenance/requests/RqZnZSVRD6d3ojcmhpaCmv
estimate: !!python/object:fc.maintenance.estimate.Estimate
  value: 600.0
last_scheduled_at: 2023-09-29 22:34:11.155626+00:00
next_due: 2023-09-30 07:30:00+00:00
state: !!python/object/apply:fc.maintenance.state.State
- '='
updated_at: null
"""


def test_legacy_reboot_activity_loading_serialization_should_work(
    logger, tmp_path
):
    request_path = tmp_path / "request.yaml"
    request_path.write_text(SERIALIZED_REQUEST)
    request = Request.load(tmp_path, logger)
    activity = request.activity
    assert activity.reboot_needed == RebootType.COLD
    assert activity.__rich__()
