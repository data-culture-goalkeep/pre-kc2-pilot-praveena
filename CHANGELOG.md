# Version history

## 0.3.0 — 2026-09-22

Overview now includes class counts, stacked gender counts by class, community counts and age distribution. Charts use enrolled students in the selected classes and expose numeric labels. Student forms and the register include optional community information. Missing community data stays explicitly unrecorded; case and whitespace variations are grouped together. Gender charts use the existing sex field.

## 0.2.0 — 2026-09-22

Three integrated tabs: Overview (class summary and student/teacher management), Attendance & growth (monthly insights and both entry forms), and Assessments (progress, competency averages and score entry). Register filters include student status and teacher name, role, status and subject. Removal retains history by recording student leaving details or deactivating teachers. Saving one entry form preserves unsaved changes in the other.

Validation: 14 automated calculation, rendering, filtering and draft-preservation checks pass. Automated browser launch was unavailable in this environment. Supabase remains unconfigured; the hosted pilot uses browser-local demo data.

## 0.1.0 — 2026-09-15

First interactive school pilot. Tamil/English interface, student and teacher registers, weekly attendance, quarterly competency assessments, monthly growth, dashboard and child profiles. Includes the 27 supplied competencies across all ten grades, WHO reference tables, local offline saving, Supabase schema with staff-only access and revision checks, and frontend deployment configuration.

Validation: 10 automated calculation/data tests pass. Browser checks cover score save and reload, height/weight save with BMI calculation, attendance save, teacher registration, student enrolment, and Tamil phone layout. Live Supabase integration is not yet configured or end-to-end tested. GitHub upload is pending private repository visibility. Hosting provider awaits resolution of the Vercel Hobby eligibility restriction.
