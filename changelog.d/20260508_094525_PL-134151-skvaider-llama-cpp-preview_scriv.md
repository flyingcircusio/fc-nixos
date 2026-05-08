<!--

A new changelog entry.

Delete placeholder items that do not apply. Empty sections will be removed
automatically during release.

Leave the XX.XX as is: this is a placeholder and will be automatically filled
correctly during the release and helps when backporting over multiple platform
branches.

-->

### Impact

<!-- Impact means "when this change is rolled out, there
     might be interruptions/downtimes/required actions/... that
     IMPACT THE RUNNING APPLICATION NEGATIVELY.

     Having new features or changed is not an "impact". That's what
     the main changelog (see below) is for.
     -->

- A bullet item for the Impact category.


### NixOS XX.XX platform

- A major rewrite of our AI inference tooling. (PL-134151)

  With the experience we made over almost 9 months we have moved away
  from AMD and our infrastructure now runs on Nvidia RTX PRO 6000 cards.

  We completely removed AMD (rocm/vulkan) support for now as it introduced
  major stability issues and we want to drive complexity down and reliability
  up.

  Also, ollama was a great way to start this journey but hasn't proven
  a good solution for a service offering. We thus replaced it with vllm
  and are now coordinating model placement over GPU clusters with our
  own tooling and can integrate different inference engines for testing
  and higher flexibility in production environments.
