/-
Feed.Derive — `lake exe derive`: print the emitted application-layer assembly
to stdout. tools/promote.sh gates what lands in gen/app_gen.s.
-/
import Feed.EmitAsm

def main : IO Unit := do
  IO.print EmitAsm.program
