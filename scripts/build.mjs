import { cp, mkdir, writeFile, rm } from 'node:fs/promises';
await rm('dist',{recursive:true,force:true}); await mkdir('dist'); await cp('public','dist',{recursive:true});
const url=process.env.SUPABASE_URL||'', key=process.env.SUPABASE_PUBLISHABLE_KEY||'';
if(key.startsWith('sb_secret_')) throw Error('Use a publishable key, never a secret key');
if(key.startsWith('eyJ')){try{if(JSON.parse(Buffer.from(key.split('.')[1],'base64url')).role!=='anon')throw Error('Only anon keys are allowed')}catch{throw Error('Invalid public key')}}
if(url && !/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url))throw Error('Expected a Supabase project URL');
await writeFile('dist/config.js',`export default ${JSON.stringify({url,key})};\n`);
console.log('Built Vanavil pilot. Database configured:',Boolean(url&&key));
