/-
Feed.Derive — `lake exe derive`: print the emitted application-layer assembly
to stdout. tools/promote.sh gates what lands in gen/app_gen.s.
-/
import Feed.EmitAuth

def main : IO Unit := do
  IO.print EmitAuth.program
