# Depthcraft package schema `0.1.0`

On-disk package is a folder (zip for transfer) named `*.depthcraft`:

```
course.depthcraft/
  manifest.json
  curriculum.json
  progress.json
  content/units/<unitId>/unit.md
  content/units/<unitId>/lessons/<lessonId>/lesson.md
  content/units/<unitId>/lessons/<lessonId>/quiz.json
  content/units/<unitId>/lessons/<lessonId>/meta.json
  assets/   # optional
```

## Pipeline
1. Planner → draft `curriculum.json` (`status: draft`)
2. Human edits map → whole-map approve (`status: approved`; optional `generateUnitIds` subset)
3. Lesson writer → `lesson.md` + `meta.json` per approved/selected lesson
4. Quiz writer → `quiz.json` (MC + cloze; cloze grade = Unicode casefold + trim)
5. Packager → validate, write `manifest.json`, init empty `progress.json`, zip

Fail closed: a failed role leaves that lesson `draft` and surfaces the error.

## Grading
- MC: `correctId` match
- Cloze: normalize both sides with Unicode casefold + trim; match any entry in `answers`
- Progress: lesson complete when read + quiz passed; unit complete when all its lessons are

Reader: native chrome + WebView for `lesson.md`; native quiz grading recommended.

## Progress ownership (product lock)

`progress.json` in a shipped/example package is a **schema fixture / empty template only**.

Runtime progress is **user/device-local state** (iCloud later). Regenerating or re-importing a course zip must **not** overwrite existing learner progress for the same `packageId` (merge/migrate by lesson id; never clobber completions).
