# Vanavil School pilot

Tamil-first, mobile-friendly school dashboard for LKG, UKG and classes 1–8. All grades currently use the supplied LKG competencies: Tamil 5, English 5, Maths 4, Library 4, Art & Craft 4, EVS 5. Score range 1–10 is provisional.

## Run and test

Node 22 or newer. No dependency installation is required.

```
npm test
npm run build
npm start
```

Open http://127.0.0.1:4173. Without database configuration the app opens a fictional 150-child demo. Demo edits are stored in this browser only and never uploaded. Clearing browser storage removes local records. Do not enter real student data in demo mode.

## Features

- Tamil/English switch; translations should be reviewed by Vanavil staff.
- Student enrolment/leaving records and optional reason.
- Daily attendance in a six-day weekly grid; holidays excluded from rate, blanks excluded and never treated as absence. Optional per-day absence reasons.
- Quarterly competency scores and matching child/competency comparisons.
- Monthly height/weight, BMI and WHO monthly age/sex reference bands for ages 24–228 months.
- Teacher roles, class and subject assignments.
- Student detail and growth history.
- IndexedDB local saving, cached app shell, and an authenticated Supabase sync queue in live mode. First use/sign-in requires internet.
- Revision checking prevents silently overwriting another device's changes. Conflict resolution needs program-lead assistance in this pilot; conflicting local records stay queued.

## Supabase setup (Free plan)

1. Create the intended Free Supabase project. Do not put credentials in GitHub.
2. Run `supabase/001_school.sql` in its SQL editor.
3. Disable public sign-ups in Authentication. Create/invite staff through the Supabase dashboard.
4. Add each user's Auth UUID to `school_staff` with their role and `approved=true`, using the SQL editor. The app cannot approve its own users.
5. Supply `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in the Vercel environment. Only use a publishable key or legacy anon key. Never use a service-role/secret key.

All approved school staff can read/edit school records, matching the pilot's requested shared access. Unapproved and anonymous users cannot read live records. RLS is enabled and writes go through a validating SQL function. Each write is audited. Local live records are isolated by signed-in user; sign-out closes access but retains that user's browser cache for offline continuity. Use school-controlled devices. A session lasts for this browser tab; fresh sign-in requires internet. No real child records are in this repository.

## Vercel

Import this repository into Vercel, choose Other, build `npm run build`, output `dist`. Add the two Supabase public environment values and redeploy for live mode. No cloud project has been provisioned by merely running this build. Verify the intended use is eligible for Vercel Hobby (personal/non-commercial terms); do not upgrade to a paid plan without explicit authorization. See https://vercel.com/docs/plans/hobby .

## Measurement conventions

BMI = kg / (cm / 100)². Age uses completed calendar months on measurement date. WHO monthly reference thresholds, not adult BMI cutoffs, classify screening bands. Ages 24–60 months use WHO child growth standards; 61–228 months use WHO 2007 reference. Below 24 months and above 228 months show BMI without a band. Tables are rounded WHO published values; this is a screening approximation, not a clinical z-score calculator. Birth date and sex must be accurate for interpretation. Low values mean below -2 SD; very low below -3 SD. Over 60 months high is above +1 SD and very high above +2 SD. Under-five high is above +2 SD, very high above +3 SD, and above +1 SD is risk of high BMI.

Source files (retrieved 2026-09-15):
- https://www.who.int/tools/growth-reference-data-for-5to19-years/indicators/bmi-for-age
- https://www.who.int/toolkits/child-growth-standards/standards/body-mass-index-for-age-bmi-for-age
- `bmi-girls-z-who-2007-exp.xlsx`, `bmi-boys-z-who-2007-exp.xlsx`
- `bmi_girls_2-to-5-years_zscores.xlsx`, `bmi_boys_2-to-5-years_zscores.xlsx`

`public/who.json` contains only the month-level -3, -2, +1, +2, +3 SD thresholds, in that order, keyed by F/M and month.

## Pilot limitations to confirm

The 75% attendance review threshold and 1–10 score scale are provisional. Calendar quarters are used until Vanavil supplies its term dates. Teacher class/subject assignments are a cross-product, not a timetable. Cohort and class filters use current classes; historical grade progression is not implemented. The dashboard reports recorded-day attendance and latest selected-quarter competencies; it cannot infer missing school days without a school calendar. The sample includes only this week's attendance. Live cloud integration and cross-device sync must be acceptance-tested once accounts are configured. Changing a competency or scoring rubric later requires versioning before comparing historical scores.
