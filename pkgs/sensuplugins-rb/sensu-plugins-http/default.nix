{ bundlerSensuPlugin }:

bundlerSensuPlugin {
  pname = "sensu-plugins-http";
  exes = [
    "check-head-redirect.rb"
    "check-http-cors.rb"
    "check-http-json.rb"
    "check-http.rb"
    "check-https-cert.rb"
    "check-last-modified.rb"
    "metrics-curl.rb"
    "metrics-http-json-deep.rb"
    "metrics-http-json.rb"
  ];
}
