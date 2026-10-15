# security

MaidShare moves files between a phone and this machine. it does not load
machine-learning models - no torch, onnx, gguf, keras or pickle anywhere -
so the model supply-chain threats (zip-slip, pickle/pytorch malcode, onnx
backdoor, gguf ssti) do not apply here.

what does apply to a file-receiving tool, and how it is handled:

- path traversal: an upload whose filename carries `..` or an absolute
  path is reduced to its basename. covered by `tests/run.sh`.
- symlink writes: a planted symlink in the destination is replaced, not
  followed, so it cannot be used to clobber a file outside the folder.
- serve root: only the chosen folder is served; `key.pem`, `cert.pem` and
  any `..` request 404. the page is token-gated and expires with the session.
- size: an oversize upload is rejected from its headers, before the body is
  read.
- transport: the https backend is TLS only; a plaintext request to the TLS
  port gets nothing back.
- no `eval`, no shell strings: python and shell both pass argv lists.

to report a problem, open an issue on the repository and keep personal
data (addresses, tokens, paths) out of it.
