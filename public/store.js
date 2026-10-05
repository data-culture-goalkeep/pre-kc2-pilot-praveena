import config from './config.js';
import {sampleData,validate,populateSampleCommunities} from './core.js';
export const configured=Boolean(config.url&&config.key);
let db,mode='demo',session=null,busy=false;let records=[];let queue=[];
let overview={students:[],enrollments:[],staff:[]};
export const snapshot=()=>records.map(r=>({...r.payload,id:r.id,kind:r.kind,revision:r.revision}));
export const pending=()=>queue.length;
export const isDemo=()=>mode==='demo';
const defaultAcademicYear=()=>{const d=new Date(),y=d.getFullYear();return d.getMonth()>=5?`${y}-${String(y+1).slice(-2)}`:`${y-1}-${String(y).slice(-2)}`};
export function overviewSnapshot(){
 if(mode==='demo'){
  const academicYear=defaultAcademicYear();
  return {
   students:records.filter(r=>r.kind==='student').map(r=>({student_id:r.id,student_name:r.payload.name,enrollment_year:r.payload.enrollmentYear||academicYear,gender:r.payload.sex==='F'?'Female':r.payload.sex==='M'?'Male':null,date_of_birth:r.payload.dob||null,social_category:r.payload.community||null,program_type:r.payload.programType||null})),
   enrollments:records.filter(r=>r.kind==='student').map(r=>({student_id:r.id,academic_year:r.payload.academicYear||academicYear,grade:r.payload.grade})),
   staff:records.filter(r=>r.kind==='teacher').map(r=>({staff_id:r.id,staff_name:r.payload.name,staff_role:r.payload.role==='School lead'?'Leadership':r.payload.role||'Teacher',email:r.payload.email||null,phone:r.payload.phone||null,grades:r.payload.grades||[],subjects:r.payload.subjects||[],joined_on:r.payload.joinedOn||null,left_on:r.payload.leftOn||null,active:r.payload.active!==false}))
  };
 }
 return structuredClone(overview);
}
function englishDemoNames(){for(const r of records){const p=r.payload;if(r.kind==='student'&&/^V\d{3}$/.test(r.id)&&/^மாதிரி மாணவர் \d+$/.test(p.name))p.name=p.name.replace('மாதிரி மாணவர்','Sample student');if(r.kind==='teacher'&&/^T\d+$/.test(r.id)&&/^மாதிரி ஆசிரியர் \d+$/.test(p.name))p.name=p.name.replace('மாதிரி ஆசிரியர்','Sample teacher')}}
const read=(store)=>new Promise((resolve,reject)=>{const req=db.transaction(store).objectStore(store).getAll();req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error)});
function transaction(stores,fn){return new Promise((resolve,reject)=>{const tx=db.transaction(stores,'readwrite');tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error||Error('Save failed'));fn(tx)})}
export async function openStore(demo=true,s=null){mode=demo?'demo':'live';session=s;if(db)db.close();db=await new Promise((resolve,reject)=>{const req=indexedDB.open(`vanavil-v1-${demo?'demo':s.user.id}`,1);req.onupgradeneeded=()=>{req.result.createObjectStore('records',{keyPath:'id'});req.result.createObjectStore('queue',{keyPath:'id'})};req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error)});records=await read('records');queue=await read('queue');if(demo&&!records.length){records=sampleData();await transaction(['records'],tx=>records.forEach(r=>tx.objectStore('records').put(r)))}if(demo){englishDemoNames();populateSampleCommunities(records);await transaction(['records'],tx=>records.filter(r=>r.kind==='student'||r.kind==='teacher').forEach(r=>tx.objectStore('records').put(r)))}return snapshot()}
export async function saveBatch(items){if(busy)throw Error('Sync in progress. Please try saving again.');items.forEach(r=>validate(r.kind,r.payload));const next=items.filter(item=>{const old=records.find(r=>r.id===item.id);return !old||JSON.stringify(old.payload)!==JSON.stringify(item.payload)}).map(item=>{const old=records.find(r=>r.id===item.id);return {...item,revision:old?.revision||0}});await transaction(['records','queue'],tx=>next.forEach(r=>{tx.objectStore('records').put(r);if(mode!=='demo')tx.objectStore('queue').put(r)}));records=await read('records');queue=await read('queue')}
async function authRequest(path,body){const r=await fetch(config.url+'/auth/v1/'+path,{method:'POST',headers:{apikey:config.key,'Content-Type':'application/json'},body:JSON.stringify(body)});const result=await r.json();if(!r.ok)throw Error(result.msg||result.error_description||'Sign in failed');return result}
export async function login(email,password){const s=await authRequest('token?grant_type=password',{email,password});await openStore(false,s);sessionStorage.setItem('vanavil-session',JSON.stringify(s));return s}
export function savedSession(){try{return JSON.parse(sessionStorage.getItem('vanavil-session'))}catch{return null}}
export function logout(){sessionStorage.removeItem('vanavil-session');session=null;if(db)db.close();db=null;records=[];queue=[]}
async function token(){if(!session)throw Error('Please sign in again.');if(session.expires_at*1000<Date.now()+60000){session=await authRequest('token?grant_type=refresh_token',{refresh_token:session.refresh_token});sessionStorage.setItem('vanavil-session',JSON.stringify(session))}return session.access_token}
async function api(path,options={}){const t=await token();const r=await fetch(config.url+'/rest/v1/'+path,{...options,headers:{apikey:config.key,Authorization:`Bearer ${t}`,'Content-Type':'application/json',...options.headers}});if(!r.ok){let error;try{error=await r.json()}catch{}throw Error(error?.message||`Sync failed (${r.status})`)}return r.status===204?null:r.json()}
export async function loadOverview(){
 if(mode==='demo')return overviewSnapshot();
 const [students,enrollments,staff]=await Promise.all([
  api('students?select=student_id,student_name,enrollment_year,gender,date_of_birth,social_category,program_type&order=student_id&limit=1000'),
  api('student_class_enrollments?select=student_id,academic_year,grade&order=academic_year.desc,grade,student_id&limit=1000'),
  api('staff_records?select=staff_id,staff_name,staff_role,email,phone,grades,subjects,joined_on,left_on,active&order=staff_name&limit=1000')
 ]);
 overview={students,enrollments,staff};
 return overviewSnapshot();
}
export async function saveOverviewStudent(row){
 if(mode==='demo'){
  const payload={name:row.student_name,grade:row.grade,sex:row.gender==='Female'?'F':row.gender==='Male'?'M':'F',dob:row.date_of_birth||'2020-01-01',enrolled:todayForDemo(row.enrollment_year),left:'',reason:'',community:row.social_category||'',programType:row.program_type||'',enrollmentYear:row.enrollment_year,academicYear:row.academic_year};
  await saveBatch([{id:row.student_id,kind:'student',payload}]);
  return loadOverview();
 }
 await api('rpc/save_overview_student',{method:'POST',body:JSON.stringify({p_student_id:row.student_id,p_student_name:row.student_name,p_enrollment_year:row.enrollment_year,p_gender:row.gender||null,p_date_of_birth:row.date_of_birth||null,p_social_category:row.social_category||null,p_program_type:row.program_type||null,p_academic_year:row.academic_year,p_grade:row.grade})});
 return loadOverview();
}
export async function saveOverviewStaff(row){
 if(mode==='demo'){
  await saveBatch([{id:row.staff_id,kind:'teacher',payload:{name:row.staff_name,role:row.staff_role,grades:row.grades,subjects:row.subjects,active:row.active,email:row.email||'',phone:row.phone||'',joinedOn:row.joined_on||'',leftOn:row.left_on||''}}]);
  return loadOverview();
 }
 await api('rpc/save_staff_record',{method:'POST',body:JSON.stringify({p_staff_id:row.staff_id,p_staff_name:row.staff_name,p_staff_role:row.staff_role,p_email:row.email||null,p_phone:row.phone||null,p_grades:row.grades,p_subjects:row.subjects,p_joined_on:row.joined_on||null,p_left_on:row.left_on||null,p_active:row.active})});
 return loadOverview();
}
function todayForDemo(year){return `${String(year||defaultAcademicYear()).slice(0,4)}-06-01`}
export async function sync(){if(mode==='demo')return 'Demo saved on this device';if(!navigator.onLine)throw Error('Offline: entries are saved on this device.');if(busy)return;busy=true;try{for(const r of [...queue].sort((a,b)=>(a.kind==='student'?0:1)-(b.kind==='student'?0:1))){const result=await api('rpc/save_school_record',{method:'POST',body:JSON.stringify({record_id:r.id,record_kind:r.kind,record_payload:r.payload,expected_revision:r.revision})});await transaction(['records','queue'],tx=>{tx.objectStore('records').put(result);tx.objectStore('queue').delete(r.id)});records=await read('records');queue=await read('queue')}
const all=[];for(let from=0;;from+=1000){const page=await api(`school_records?select=*&order=id&offset=${from}&limit=1000`);all.push(...page);if(page.length<1000)break}await transaction(['records'],tx=>{tx.objectStore('records').clear();all.forEach(r=>tx.objectStore('records').put(r))});records=all;return 'All changes synced';}finally{busy=false}}
