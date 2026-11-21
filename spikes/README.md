# Spikes

A spike is throwaway code that answers one question. It lives here only
while the question is open.

1. Give each spike a dex task with a `Type: prototype` or `Type: research` line. Name the folder after the question.
2. When the question has an answer, write the answer in the dex task result. Write a research note or an ADR if the answer matters beyond the task.
3. In the same commit, delete the spike folder, or move the code worth keeping into `engine/`, `scripts/` or `examples/` with real tests.
4. Do not build a spike in CI or in `scripts/pre-push.sh`. If a check in a spike is worth keeping, move it out of the spike first. `scripts/pre-push.sh` refuses a CI workflow that names `spikes/`.
