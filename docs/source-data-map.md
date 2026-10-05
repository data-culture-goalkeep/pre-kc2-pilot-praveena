# Vanavil source data map

Reviewed from the shared KC2 sample-data folder on 2026-10-05.

## Student details

Workbook: `Copy of [Stagging] Students & Attendance | Vanavil`

- `Students` is the authoritative student register.
- Columns: student ID, name, enrollment year, gender, date of birth, social category, program type, and class for AY 2025-26, 2026-27 and 2027-28.
- 188 rows currently have both an ID and a name. Another 60 rows contain only reserved IDs and should not be imported as students.
- 31 named students have no date of birth. The database therefore permits a missing DOB; BMI-for-age remains unavailable until it is supplied.
- Class must be stored by academic year. A single current-grade field loses progression history.

## Attendance and growth

The same workbook contains these class tabs:

- `LKG_Attn`
- `UKG_Attn`
- `Class1_Attn` through `Class8_Attn`

Each row represents one student-month and contains academic year, month, age, height, weight, calculated BMI, days 1-31, present/absent totals and attendance percentage. Daily markers are `P`, `A` and `H` for present, absent and holiday.

Import rules:

- Expand each valid day column into one daily attendance row.
- Store height and weight once per student-month; calculate BMI in the database/dashboard.
- Recalculate monthly attendance from daily rows rather than importing spreadsheet totals.
- Ignore spreadsheet BMI category during import. The dashboard uses DOB, sex and WHO age-specific reference data.

## Assessments

There is one assessment workbook per grade: LKG, UKG and Classes 1-8. Each workbook contains:

- hidden `Grade-Assessment-Map`: competency and three activity definitions;
- hidden `Students_Import` and `Dropdown-Range` helper tabs;
- one visible tab per subject containing student, academic year, term and activity-level scores.

Subjects are Tamil, English, Maths, Library and Art & Craft for every grade. LKG-Class 4 use EVS. Classes 5-8 use Science and Social Science.

The source scoring model differs from the original pilot:

- periods are `Baseline`, `Term 1`, `Term 2` and `Term 3`, not calendar quarters;
- scores can be 0-10;
- every competency has up to three activity scores;
- competency scores are derived as the mean of recorded activity scores;
- Maths has an additional `Sums (Oral / Written)` competency from Class 1 onward;
- EVS, Science and Social Science include a sixth `Research` competency.

Some rubric cells still contain `<activity_name>`, and some labels vary (`Student Work`/`Students Work`, `Show& Tell`/`Show & Tell`). These should be cleaned or approved before production import. The assessment map has definitions through Class 7; the Class 8 workbook follows the Class 7 structure but needs Vanavil confirmation before its rubric is treated as final.

## Database mapping

- `students`: stable student identity and demographic details.
- `student_class_enrollments`: one class per student and academic year.
- `attendance_daily`: one student/date status.
- `growth_measurements`: one height/weight measurement per student/date with generated BMI.
- `assessment_rubrics`: grade/subject/competency/activity definitions.
- `assessment_activity_scores`: student activity scores by academic year and term.
- `attendance_monthly_summary`: derived attendance view.
- `assessment_competency_scores`: derived competency-average view.

The original `school_records`, `school_record_history` and `school_staff` tables remain in place for the current pilot frontend and audit trail.
