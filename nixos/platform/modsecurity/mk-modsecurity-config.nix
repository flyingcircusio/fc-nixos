{
  lib,
  pkgs,
  rules,
}:
''
  ${
    if rules.coreRuleSet.blocking then
      ''
        SecRuleEngine On

        SecDefaultAction "phase:1,log,auditlog,pass"
        SecDefaultAction "phase:2,log,auditlog,pass"

        SecAction \
         "id:900110,\
          phase:1,\
          nolog,\
          pass,\
          t:none,\
          setvar:tx.inbound_anomaly_score_threshold=${toString rules.coreRuleSet.anomalyThreshold.inbound},\
          setvar:tx.outbound_anomaly_score_threshold=${toString rules.coreRuleSet.anomalyThreshold.outbound}"
      ''
    else
      ''
        SecRuleEngine DetectionOnly

        SecDefaultAction "phase:1,log,auditlog,pass"
        SecDefaultAction "phase:2,log,auditlog,pass"
      ''
  }

  SecRequestBodyAccess ${if rules.requestBody.access then "On" else "Off"}
  SecDebugLog ${rules.debugLog.path}
  SecDebugLogLevel ${toString rules.debugLog.level}
  SecAuditEngine ${rules.audit.engine}
  SecAuditLogParts ${rules.audit.log.parts}
  SecAuditLogFormat ${rules.audit.log.format}
  SecAuditLogType ${rules.audit.log.type}
  SecAuditLog ${rules.audit.log.path}
  SecUnicodeMapFile ${pkgs.libmodsecurity.src}/unicode.mapping 20127
  SecCollectionTimeout ${toString rules.collectionTimeout}

  ${lib.optionalString (rules.coreRuleSet.enable) ''
    SecAction \
     "id:900990,\
      phase:1,\
      nolog,\
      pass,\
      t:none,\
      setvar:tx.crs_setup_version=${pkgs.modsecurity-crs.version}"

    include ${pkgs.modsecurity-crs}/rules/*.conf
  ''}

  ${rules.extraConfig}
''
