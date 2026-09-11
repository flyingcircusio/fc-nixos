# Wazuh Agent Package

Decision log for build patches and dependency handling. Each entry records what changed, why, and the upstream source where relevant.

For the NixOS module, see `nixos/services/wazuh/agent.nix`.

## Build Targets

Only the **agent** target is supported. Manager (server/local/hybrid) is out of scope.

```sh
make TARGET=agent
```

## Common Build Errors

If a build fails, check the errors below. These crop up when dependencies change or versions shift.

### External-dependencies base URL

The `prefetch-external-dependencies.sh` script fetches dependencies from Wazuh's servers. It uses `https://packages.wazuh.com/deps/$DEPENDENCY_VERSION/libraries/sources` as the base URL. There's also `https://packages.wazuh.com/deps/$DEPENDENCY_VERSION/libraries/linux/amd64` for prebuilt binaries, but we build from source instead.

### External-dependencies failure

If you see something like:

```sh
curl -so external/cpython.tar.gz https://packages.wazuh.com/deps/51/libraries/linux/amd64/cpython.tar.gz || true
cd external && [ -f cpython.tar.gz ] && gunzip cpython.tar.gz || true
test -e external/cpython.tar || \
(curl -so external/cpython.tar.gz https://packages.wazuh.com/deps/51/libraries/sources/cpython_x86_64.tar.gz && \
cd external && gunzip cpython.tar.gz && tar -xf cpython.tar && rm cpython.tar)
make: *** [Makefile:1503: external/cpython.tar.gz] Error 6
make: Leaving directory '/build/src'
```

The build tries to download dependencies at build time. In the Nix sandbox there's no network access, so `curl` fails — but the Makefile continues anyway due to `|| true`. We prefetch dependencies with `fetchurl` and place them where Wazuh expects them, so the failed download doesn't matter.

The relevant Makefile logic lives at `src/Makefile:1503` as of Wazuh 4.14.5.

This error indicates either a missing dependency or an incorrect name. With `cpython` specifically, the source tarball has a `_x86_64` suffix but the Makefile expects `cpython.tar.gz`. Fix this by adding a rename step in `default.nix` using a `let in` expression with `fetchurl`.

For a missing dependency, add its name under `{url}` in `prefetch-external-dependencies.sh` and run the script.

## Patches

### 01-makefile-patch.patch

**`$(DB_LIB)` linkage**

```diff
-EXTERNAL_LIBS += $(PROCPS_LIB) $(LIBALPM_LIB) $(LIBARCHIVE_LIB)
+EXTERNAL_LIBS += $(PROCPS_LIB) $(LIBALPM_LIB) $(LIBARCHIVE_LIB) $(DB_LIB)
```

Adds database library linkage. Wazuh builds DB support conditionally — without this the agent build fails with unresolved symbols.

**OpenSSL `Configure` via Perl**

```diff
-	cd ${EXTERNAL_OPENSSL} && ./config $(OPENSSL_FLAGS) && ${MAKE} build_libs
+	cd ${EXTERNAL_OPENSSL} && perl ./Configure $(OPENSSL_FLAGS) && ${MAKE} build_libs
```

OpenSSL's `./config` wrapper doesn't find Perl in the Nix sandbox. Calling `Configure` directly with explicit `perl` bypasses this.

**`Privsep_SetUser`/`SetGroup` early return**

```diff
 int Privsep_SetUser(uid_t uid)
 {
+    return(OS_SUCCESS);
+
     if (setuid(uid) < 0) {
         return (OS_INVALID);
     }
```

The agent runs under systemd with `User=`/`Group=` set, so it already runs as the correct user. Without this early return, `setuid()`/`setgid()` fail because the process doesn't have root privileges — it runs with `AmbientCapabilities`, not as root.

**`file_op.c` `w_homedir()` — `WAZUH_HOME` check** *(new in v4.14.5)*

Adds `WAZUH_HOME` env var check as first priority in home directory resolution. Without this, `/proc/self/exe` resolves to `/nix/store/...` instead of `/var/ossec`.

### 02-libbpf-bootstrap.patch

**Disable git fetching**

```diff
 ExternalProject_Add(libbpf
   PREFIX libbpf
-  GIT_REPOSITORY https://github.com/libbpf/libbpf.git
-  GIT_TAG v1.5.0
   SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/libbpf
   ...
+  DOWNLOAD_COMMAND ""
   STEP_TARGETS build
 )
```

libbpf-bootstrap is fetched via `fetchFromGitHub` with `fetchSubmodules = true`, so all submodules are already present. The `DOWNLOAD_COMMAND ""` disables CMake's git clone, which would fail in the sandbox without network access.

**Disable `modern.bpf.c` download**

```diff
-set(FILE_URL "https://raw.githubusercontent.com/wazuh/wazuh/${WAZUH_BRANCH}/src/syscheckd/src/ebpf/src/modern.bpf.c")
+#set(FILE_URL "https://raw.githubusercontent.com/wazuh/wazuh/${WAZUH_BRANCH}/src/syscheckd/src/ebpf/src/modern.bpf.c")
...
-#file(DOWNLOAD ${FILE_URL} ${DEST_PATH})
-#file(SIZE ${DEST_PATH} FILE_SIZE)
```

Disables the built-in fetching of `modern.bpf.c`, replaced by `fetchurl`. The checksum-based verification from `fetchurl` makes the if-not-exists check redundant.

**Suppress eBPF compiler warnings**

```diff
+set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-error=implicit-function-declaration -Wno-error=int-conversion")
 bpf_object(modern src/modern.bpf.c)
```

GCC 15 in nixpkgs promotes `implicit-function-declaration` and `int-conversion` from warnings to errors. The eBPF code has these issues but compiles correctly despite them.

### 03-cstdint-include.patch

Adds `#include <cstdint>` to `src/shared_modules/dbsync/src/sqlite/sqlite_wrapper.h`.

As of v4.14.5, upstream already includes `<cstdint>` in `isqlite_wrapper.h` and `stringHelper.h`. Only `sqlite_wrapper.h` still needs the patch.

Required because modern compilers (GCC 14+) enforce stricter include requirements for `<cstdint>` types like `uint8_t`.

### 04-snap-onerror-signature.patch

Upstream v4.14.5 passes a 3-parameter lambda `(result, responseCode, responseBody)` as `PostRequestParameters.onError`, but the type signature expects 2 parameters `(result, responseCode)`. GCC 15 rejects this mismatch. The patch drops the `responseBody` parameter.
