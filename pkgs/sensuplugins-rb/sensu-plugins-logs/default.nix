{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-logs";
  exes = [
    "check-journal.rb"
    "check-log.rb"
    "handler-logevent.rb"
    "handler-show-event-config.rb"
  ];
}
