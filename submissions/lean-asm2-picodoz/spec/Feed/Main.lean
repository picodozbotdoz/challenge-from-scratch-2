/-
M0 bootstrap sanity target: builds under the 2 GiB cap, prints one line.
Replaced by the real SpecCheck in M1.
-/
def main : IO Unit := IO.println "bootstrap: spec project builds under the 2G cap"
