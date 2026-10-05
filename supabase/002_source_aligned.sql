-- Source-aligned tables for the Vanavil sample workbooks.
-- This migration is additive: the pilot's school_records tables remain intact.
begin;

create or replace function public.is_approved_school_staff()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.school_staff
    where user_id = auth.uid() and approved
  );
$$;
revoke all on function public.is_approved_school_staff() from public, anon;
grant execute on function public.is_approved_school_staff() to authenticated;

create table if not exists public.students (
  student_id text primary key,
  student_name text not null check (length(trim(student_name)) > 0),
  enrollment_year text not null check (enrollment_year ~ '^20[0-9]{2}-[0-9]{2}$'),
  gender text check (gender in ('Female', 'Male') or gender is null),
  date_of_birth date,
  social_category text check (social_category in ('SC','ST','MBC','BC','General','Others') or social_category is null),
  program_type text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (date_of_birth is null or date_of_birth <= current_date)
);

create table if not exists public.student_class_enrollments (
  student_id text not null references public.students(student_id) on delete cascade,
  academic_year text not null check (academic_year ~ '^20[0-9]{2}-[0-9]{2}$'),
  grade text not null check (grade in ('LKG','UKG','1','2','3','4','5','6','7','8')),
  primary key (student_id, academic_year)
);

create table if not exists public.attendance_daily (
  student_id text not null references public.students(student_id) on delete cascade,
  attendance_date date not null,
  academic_year text not null check (academic_year ~ '^20[0-9]{2}-[0-9]{2}$'),
  grade text not null check (grade in ('LKG','UKG','1','2','3','4','5','6','7','8')),
  status text not null check (status in ('present','absent','holiday')),
  absence_reason text,
  primary key (student_id, attendance_date)
);
create index if not exists attendance_daily_year_grade_date
  on public.attendance_daily(academic_year, grade, attendance_date);

create table if not exists public.growth_measurements (
  student_id text not null references public.students(student_id) on delete cascade,
  measured_on date not null,
  academic_year text not null check (academic_year ~ '^20[0-9]{2}-[0-9]{2}$'),
  grade text not null check (grade in ('LKG','UKG','1','2','3','4','5','6','7','8')),
  height_cm numeric(5,2) not null check (height_cm between 50 and 220),
  weight_kg numeric(5,2) not null check (weight_kg between 5 and 150),
  bmi numeric(5,2) generated always as
    (round((weight_kg / power(height_cm / 100, 2))::numeric, 2)) stored,
  primary key (student_id, measured_on)
);

create table if not exists public.assessment_rubrics (
  grade text not null check (grade in ('LKG','UKG','1','2','3','4','5','6','7','8')),
  subject text not null,
  competency_order smallint not null check (competency_order > 0),
  competency text not null,
  activity_order smallint not null check (activity_order between 1 and 3),
  activity text,
  primary key (grade, subject, competency_order, activity_order)
);

create table if not exists public.assessment_activity_scores (
  student_id text not null references public.students(student_id) on delete cascade,
  academic_year text not null check (academic_year ~ '^20[0-9]{2}-[0-9]{2}$'),
  term text not null check (term in ('Baseline','Term 1','Term 2','Term 3')),
  grade text not null check (grade in ('LKG','UKG','1','2','3','4','5','6','7','8')),
  subject text not null,
  competency_order smallint not null check (competency_order > 0),
  competency text not null,
  activity_order smallint not null check (activity_order between 1 and 3),
  activity text not null,
  score numeric(4,2) check (score between 0 and 10),
  primary key (student_id, academic_year, term, subject, competency_order, activity_order)
);
create index if not exists assessment_scores_cohort
  on public.assessment_activity_scores(academic_year, grade, term, subject);

create or replace view public.assessment_competency_scores
with (security_invoker = true) as
select student_id, academic_year, term, grade, subject,
       competency_order, competency, round(avg(score), 2) as score,
       count(score) as activities_scored
from public.assessment_activity_scores
group by student_id, academic_year, term, grade, subject,
         competency_order, competency;

create or replace view public.attendance_monthly_summary
with (security_invoker = true) as
select student_id, academic_year, grade,
       date_trunc('month', attendance_date)::date as month_start,
       count(*) filter (where status = 'present') as days_present,
       count(*) filter (where status = 'absent') as days_absent,
       count(*) filter (where status = 'holiday') as holidays,
       round(100.0 * count(*) filter (where status = 'present') /
         nullif(count(*) filter (where status in ('present','absent')), 0), 2) as attendance_percent
from public.attendance_daily
group by student_id, academic_year, grade, date_trunc('month', attendance_date);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'students','student_class_enrollments','attendance_daily',
    'growth_measurements','assessment_rubrics','assessment_activity_scores'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('drop policy if exists approved_staff_all on public.%I', table_name);
    execute format(
      'create policy approved_staff_all on public.%I for all to authenticated using (public.is_approved_school_staff()) with check (public.is_approved_school_staff())',
      table_name
    );
    execute format('revoke all on public.%I from anon, authenticated', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
  end loop;
end $$;

grant select on public.assessment_competency_scores to authenticated;
grant select on public.attendance_monthly_summary to authenticated;

commit;
