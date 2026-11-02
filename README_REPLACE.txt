NEW REPOSITORY NAME
  ttsky-kalman1bit-shared-alu

SOURCE BASELINE
  https://github.com/nysmlk161160-commits/ttsky-kalman1bitfulladder-optimized

WHAT TO DO
  1. Open https://github.com/TinyTapeout/ttsky-verilog-template
  2. Click "Use this template" -> "Create a new repository".
  3. Name the repository: ttsky-kalman1bit-shared-alu
  4. Open the new repo, then upload/overwrite these files at their exact paths:
       src/project.v         REQUIRED: updated shared top-level ALU RTL
       src/config.json       REQUIRED: baseline physical constraints
       info.yaml             REQUIRED: project name, top, clock, pinout
       test/test.py          REQUIRED: original 65-vector Cocotb test
       test/Makefile         RECOMMENDED: matching RTL/GL simulation setup
       test/tb.v             RECOMMENDED: matching Tiny Tapeout test wrapper
       docs/info.md          RECOMMENDED: project documentation
       README.md             OPTIONAL: experiment overview
  5. Keep the NEW TEMPLATE's .github/workflows and .devcontainer untouched.
     Do not upload/delete the template's workflow files.
  6. Commit changes. Check Actions: gds, precheck, gl_test, and viewer.
  7. Compare RTL test first, then routed PPA. Save full metrics.csv/json.

IMPORTANT
  - Unzip this archive. When uploading to GitHub, preserve the directory paths.
  - top_module remains tt_um_example and all interface pins are unchanged.
  - The serial DIV and MUL modules are unchanged; only top-level add/sub is shared.
  - CLOCK_PERIOD = 20 ns, PL_TARGET_DENSITY_PCT = 75; same as original repo.
  - Gate-level latency measured 268 cycles in the earlier baseline; test timing
    can differ from RTL by one sampled cycle, so distinguish RTL vs GL.
  - No routed PPA improvement is assumed. Obtain data from the new Actions run.
  - You can compare RTL cycle counts with the baseline (normal: 267; fast: 189).

NOTE ON VERIFICATION
  Verilog simulator and Cocotb may not be installed in the local generation
  environment. The supplied test/test.py should run in GitHub's workflow.
  - Protocol requirement: do not assert write-enable and start together. The
    new design computes delta one edge later and therefore differs from the
    baseline for simultaneous write+start when Z/X are written that edge.
  - Upload extracted files/folders, NOT the ZIP itself as a GitHub source file.
    If the GitHub upload page does not replace an existing path, open that file
    in GitHub, click Edit, paste the corresponding extracted file and commit.
