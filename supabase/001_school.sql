-- Apply once in the Supabase SQL editor. No student records are included.
begin;
create table public.school_staff (
 user_id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('teacher','program','leadership')),
 approved boolean not null default false
);
alter table public.school_staff enable row level security;
create policy read_own_membership on public.school_staff for select to authenticated using (user_id=auth.uid());
revoke all on public.school_staff from anon,authenticated;
grant select on public.school_staff to authenticated;
create table public.school_records (
 id text primary key check(length(id) between 1 and 200),
 kind text not null check(kind in ('student','teacher','attendance','assessment','growth')),
 payload jsonb not null check(jsonb_typeof(payload)='object'),
 revision integer not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id)
);
create index school_records_kind on public.school_records(kind);
alter table public.school_records enable row level security;
create policy staff_read on public.school_records for select to authenticated using (
 exists(select 1 from public.school_staff where user_id=auth.uid() and approved)
);
revoke all on public.school_records from anon,authenticated;
grant select on public.school_records to authenticated;
create table public.school_record_history (
 history_id bigint generated always as identity primary key,
 record_id text not null,
 kind text not null,
 payload jsonb not null,
 revision integer not null,
 changed_at timestamptz not null default now(),
 changed_by uuid references auth.users(id)
);
alter table public.school_record_history enable row level security;
revoke all on public.school_record_history from anon,authenticated;
-- Clients can only write through this validating, conflict-aware function.
create function public.save_school_record(record_id text,record_kind text,record_payload jsonb,expected_revision integer)
returns public.school_records language plpgsql security definer set search_path=public,pg_temp as $$
declare old public.school_records; result public.school_records; p jsonb:=record_payload;
 valid_competencies text[]; child jsonb; score numeric; d date;
begin
 if not exists(select 1 from public.school_staff where user_id=auth.uid() and approved) then raise exception 'Approved school access is required'; end if;
 if record_id is null or record_id !~ '^[A-Za-z0-9 :/&_.-]+$' or length(record_id)>200 or length(record_id)<1 or jsonb_typeof(p)<>'object' or octet_length(p::text)>20000 then raise exception 'Invalid record'; end if;
 if expected_revision<0 then raise exception 'Invalid revision'; end if;
 perform pg_advisory_xact_lock(hashtextextended(record_id,0));
 select * into old from public.school_records where id=record_id for update;
 -- A response lost after a successful save is safe to retry.
 if old.id is not null and old.revision=expected_revision+1 and old.kind=record_kind and old.payload=p then return old; end if;
 if coalesce(old.revision,0)<>expected_revision then raise exception 'Another device changed this record. Your local entry is retained; ask the program lead to resolve the conflict.'; end if;
 if old.id is not null and old.kind<>record_kind then raise exception 'Record type cannot change'; end if;
 if record_kind='student' then
  if coalesce(length(trim(p->>'name')),0)=0 or not coalesce(p->>'grade'=any(array['LKG','UKG','1','2','3','4','5','6','7','8']),false) or not coalesce(p->>'sex'=any(array['F','M']),false) or p->>'dob' is null or p->>'enrolled' is null then raise exception 'Invalid student'; end if;
  if (p->>'dob')::date>(p->>'enrolled')::date or (p->>'enrolled')::date>current_date or (nullif(p->>'left',''))::date<(p->>'enrolled')::date then raise exception 'Check student dates'; end if;
 elsif record_kind='teacher' then
  if coalesce(length(trim(p->>'name')),0)=0 or coalesce(length(trim(p->>'role')),0)=0 or jsonb_typeof(p->'grades') is distinct from 'array' or jsonb_typeof(p->'subjects') is distinct from 'array' or jsonb_typeof(p->'active') is distinct from 'boolean' then raise exception 'Invalid teacher'; end if;
 elsif record_kind in ('attendance','assessment','growth') then
  select payload into child from public.school_records where id=p->>'student' and kind='student';
  if child is null then raise exception 'Student record is missing'; end if;
  if record_kind='attendance' then
   if not coalesce(p->>'status'=any(array['present','absent','holiday']),false) or p->>'date' is null then raise exception 'Invalid attendance'; end if;
   d:=(p->>'date')::date;
   if d>current_date or d<(child->>'enrolled')::date or d>coalesce(nullif(child->>'left','')::date,d) or record_id<>('a:'||(p->>'student')||':'||(p->>'date')) then raise exception 'Invalid attendance date or key'; end if;
  elsif record_kind='assessment' then
   valid_competencies:=case p->>'subject'
    when 'Tamil' then array['Understanding','Reading','Expression','Writing','Critical and Creative Thinking']
    when 'English' then array['Understanding','Reading','Expression','Writing','Critical and Creative Thinking']
    when 'Maths' then array['Counting / Number System','Measuring','Concepts Understanding','Geometry']
    when 'Library' then array['Reading and Comprehension','Expression and Creativity','Critical Thinking / Curiosity','Community & Library']
    when 'Art & Craft' then array['Creative Expression','Skill / Artistic Practice','Collaboration / Participation','Cultural Connection & Reflection']
    when 'EVS' then array['Conceptual Understanding','Field Data Collection / Documentation','Analysis','Presentation','Critical / Creative Thinking'] end;
   if not coalesce(p->>'competency'=any(valid_competencies),false) or not coalesce(p->>'period' ~ '^\d{4}-Q[1-4]$',false) or jsonb_typeof(p->'score') is distinct from 'number' then raise exception 'Invalid assessment'; end if;
   score:=(p->>'score')::numeric;
   if score<1 or score>10 or score<>trunc(score) then raise exception 'Use whole scores 1–10'; end if;
   if record_id<>('s:'||(p->>'student')||':'||(p->>'period')||':'||(p->>'subject')||':'||(array_position(valid_competencies,p->>'competency')-1)::text) then raise exception 'Invalid assessment key'; end if;
  else
   if p->>'date' is null or jsonb_typeof(p->'weight') is distinct from 'number' or jsonb_typeof(p->'height') is distinct from 'number' then raise exception 'Invalid measurement'; end if;
   d:=(p->>'date')::date;
   if (p->>'height')::numeric not between 50 and 220 or (p->>'weight')::numeric not between 5 and 150 or d>current_date or d<(child->>'enrolled')::date or record_id<>('g:'||(p->>'student')||':'||to_char(d,'YYYY-MM')) then raise exception 'Check measurement values and date'; end if;
  end if;
 else raise exception 'Invalid record type'; end if;
 insert into public.school_records(id,kind,payload,revision,updated_by) values(record_id,record_kind,p,expected_revision+1,auth.uid())
 on conflict(id) do update set payload=excluded.payload,revision=excluded.revision,updated_at=now(),updated_by=auth.uid() returning * into result;
 insert into public.school_record_history(record_id,kind,payload,revision,changed_by) values(result.id,result.kind,result.payload,result.revision,auth.uid());
 return result;
end $$;
revoke all on function public.save_school_record(text,text,jsonb,integer) from public,anon;
grant execute on function public.save_school_record(text,text,jsonb,integer) to authenticated;
commit;
