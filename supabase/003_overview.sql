-- Normalized staff records and guarded Overview writes.
begin;

create table if not exists public.staff_records (
  staff_id text primary key check (staff_id ~ '^[A-Za-z0-9_.-]{1,80}$'),
  staff_name text not null check (length(trim(staff_name)) > 0),
  staff_role text not null check (staff_role in ('Teacher','Program','Leadership','Support')),
  email text,
  phone text,
  grades text[] not null default '{}',
  subjects text[] not null default '{}',
  joined_on date,
  left_on date,
  active boolean not null default true,
  user_id uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (left_on is null or joined_on is null or left_on >= joined_on),
  check (grades <@ array['LKG','UKG','1','2','3','4','5','6','7','8']::text[]),
  check (subjects <@ array['Tamil','English','Maths','Library','Art & Craft','EVS','Science','Social Science']::text[])
);

create table if not exists public.overview_change_history (
  history_id bigint generated always as identity primary key,
  entity_type text not null check (entity_type in ('student','staff')),
  entity_id text not null,
  snapshot jsonb not null,
  changed_at timestamptz not null default now(),
  changed_by uuid references auth.users(id)
);

alter table public.staff_records enable row level security;
drop policy if exists approved_staff_read on public.staff_records;
create policy approved_staff_read on public.staff_records for select to authenticated
using (public.is_approved_school_staff());

alter table public.overview_change_history enable row level security;
drop policy if exists approved_staff_history_read on public.overview_change_history;
create policy approved_staff_history_read on public.overview_change_history for select to authenticated
using (public.is_approved_school_staff());

revoke all on public.staff_records, public.overview_change_history from anon, authenticated;
grant select on public.staff_records, public.overview_change_history to authenticated;

create or replace function public.save_overview_student(
  p_student_id text,
  p_student_name text,
  p_enrollment_year text,
  p_gender text,
  p_date_of_birth date,
  p_social_category text,
  p_program_type text,
  p_academic_year text,
  p_grade text
) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare result jsonb;
begin
  if not public.is_approved_school_staff() then
    raise exception 'Approved school access is required';
  end if;
  if p_student_id is null or p_student_id !~ '^[A-Za-z0-9_.-]{1,80}$'
     or coalesce(length(trim(p_student_name)),0) = 0
     or p_enrollment_year !~ '^20[0-9]{2}-[0-9]{2}$'
     or p_academic_year !~ '^20[0-9]{2}-[0-9]{2}$'
     or p_grade is null or p_grade <> all(array['LKG','UKG','1','2','3','4','5','6','7','8'])
     or (p_gender is not null and p_gender <> all(array['Female','Male']))
     or (p_social_category is not null and p_social_category <> all(array['SC','ST','MBC','BC','General','Others']))
     or p_date_of_birth > current_date then
    raise exception 'Check student ID, name, academic years, class and demographic values';
  end if;

  insert into public.students(
    student_id, student_name, enrollment_year, gender, date_of_birth,
    social_category, program_type, updated_at
  ) values (
    trim(p_student_id), trim(p_student_name), p_enrollment_year,
    nullif(p_gender,''), p_date_of_birth, nullif(p_social_category,''),
    nullif(trim(p_program_type),''), now()
  )
  on conflict (student_id) do update set
    student_name = excluded.student_name,
    enrollment_year = excluded.enrollment_year,
    gender = excluded.gender,
    date_of_birth = excluded.date_of_birth,
    social_category = excluded.social_category,
    program_type = excluded.program_type,
    updated_at = now();

  insert into public.student_class_enrollments(student_id, academic_year, grade)
  values (trim(p_student_id), p_academic_year, p_grade)
  on conflict (student_id, academic_year) do update set grade = excluded.grade;

  select jsonb_build_object(
    'student_id', s.student_id,
    'student_name', s.student_name,
    'enrollment_year', s.enrollment_year,
    'gender', s.gender,
    'date_of_birth', s.date_of_birth,
    'social_category', s.social_category,
    'program_type', s.program_type,
    'academic_year', e.academic_year,
    'grade', e.grade
  ) into result
  from public.students s
  join public.student_class_enrollments e on e.student_id = s.student_id
  where s.student_id = trim(p_student_id) and e.academic_year = p_academic_year;

  insert into public.overview_change_history(entity_type, entity_id, snapshot, changed_by)
  values ('student', trim(p_student_id), result, auth.uid());
  return result;
end;
$$;

create or replace function public.save_staff_record(
  p_staff_id text,
  p_staff_name text,
  p_staff_role text,
  p_email text,
  p_phone text,
  p_grades text[],
  p_subjects text[],
  p_joined_on date,
  p_left_on date,
  p_active boolean
) returns public.staff_records
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare result public.staff_records;
begin
  if not public.is_approved_school_staff() then
    raise exception 'Approved school access is required';
  end if;
  if p_staff_id is null or p_staff_id !~ '^[A-Za-z0-9_.-]{1,80}$'
     or coalesce(length(trim(p_staff_name)),0) = 0
     or p_staff_role is null or p_staff_role <> all(array['Teacher','Program','Leadership','Support'])
     or not coalesce(p_grades,'{}') <@ array['LKG','UKG','1','2','3','4','5','6','7','8']::text[]
     or not coalesce(p_subjects,'{}') <@ array['Tamil','English','Maths','Library','Art & Craft','EVS','Science','Social Science']::text[]
     or (p_left_on is not null and p_joined_on is not null and p_left_on < p_joined_on) then
    raise exception 'Check staff ID, name, role, assignments and dates';
  end if;

  insert into public.staff_records(
    staff_id, staff_name, staff_role, email, phone, grades, subjects,
    joined_on, left_on, active, updated_at
  ) values (
    trim(p_staff_id), trim(p_staff_name), p_staff_role, nullif(trim(p_email),''),
    nullif(trim(p_phone),''), coalesce(p_grades,'{}'), coalesce(p_subjects,'{}'),
    p_joined_on, p_left_on, coalesce(p_active,true), now()
  )
  on conflict (staff_id) do update set
    staff_name = excluded.staff_name,
    staff_role = excluded.staff_role,
    email = excluded.email,
    phone = excluded.phone,
    grades = excluded.grades,
    subjects = excluded.subjects,
    joined_on = excluded.joined_on,
    left_on = excluded.left_on,
    active = excluded.active,
    updated_at = now()
  returning * into result;

  insert into public.overview_change_history(entity_type, entity_id, snapshot, changed_by)
  values ('staff', result.staff_id, to_jsonb(result), auth.uid());
  return result;
end;
$$;

revoke all on function public.save_overview_student(text,text,text,text,date,text,text,text,text) from public, anon;
grant execute on function public.save_overview_student(text,text,text,text,date,text,text,text,text) to authenticated;
revoke all on function public.save_staff_record(text,text,text,text,text,text[],text[],date,date,boolean) from public, anon;
grant execute on function public.save_staff_record(text,text,text,text,text,text[],text[],date,date,boolean) to authenticated;

-- Preserve any teacher records already collected through the pilot JSON model.
insert into public.staff_records(staff_id, staff_name, staff_role, grades, subjects, active)
select r.id,
       r.payload->>'name',
       case lower(coalesce(r.payload->>'role',''))
         when 'school lead' then 'Leadership'
         when 'program' then 'Program'
         when 'support' then 'Support'
         else 'Teacher'
       end,
       coalesce(array(select jsonb_array_elements_text(r.payload->'grades')), '{}'),
       coalesce(array(select jsonb_array_elements_text(r.payload->'subjects')), '{}'),
       coalesce((r.payload->>'active')::boolean, true)
from public.school_records r
where r.kind = 'teacher' and coalesce(length(trim(r.payload->>'name')),0) > 0
on conflict (staff_id) do nothing;

commit;
