/** Compile against the existing, locked Keycloak distribution. No dependency resolver. */
import { spawn } from 'node:child_process';
import { mkdir, mkdtemp, readFile, readdir, cp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, delimiter, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root=dirname(fileURLToPath(import.meta.url));
const lock=JSON.parse(await readFile(join(root,'../deploy/runtime-lock.json'),'utf8'));
const args=process.argv.slice(2);
if(args.length!==4||args[0]!=='--distribution'||args[2]!=='--output')throw new Error('Usage: node infra/identity/build-provider.mjs --distribution KEYCLOAK_HOME --output PROVIDER.jar');
const distribution=resolve(args[1]),output=resolve(args[3]);
const libraries=join(distribution,'lib/lib/main');
const libraryNames=await readdir(libraries);
for(const artifact of ['keycloak-core','keycloak-services','keycloak-server-spi','keycloak-server-spi-private']) {
  if(!libraryNames.includes(`org.keycloak.${artifact}-${lock.keycloak.version}.jar`))throw new Error('KEYCLOAK_LOCKED_DISTRIBUTION_REQUIRED');
  if(libraryNames.some(name=>name.startsWith(`org.keycloak.${artifact}-`)&&/^\d/.test(name.slice(`org.keycloak.${artifact}-`.length))&&name!==`org.keycloak.${artifact}-${lock.keycloak.version}.jar`))throw new Error('KEYCLOAK_MIXED_VERSIONS_REFUSED');
}
const javaTool=name=>process.env.JAVA_HOME?join(process.env.JAVA_HOME,'bin',name+(process.platform==='win32'?'.exe':'')):name;
function run(command,args) {return new Promise((done,fail)=>{const child=spawn(command,args,{stdio:'inherit',windowsHide:true});child.on('error',fail);child.on('exit',code=>code===0?done():fail(new Error('IDENTITY_PROVIDER_BUILD_FAILED')));});}
const temporary=await mkdtemp(join(tmpdir(),'drivy-identity-build-'));
try {
  const classes=join(temporary,'classes');await mkdir(classes);
  await run(javaTool('javac'),['--release','21','-encoding','UTF-8','-g:none','-proc:none','-classpath',join(libraries,'*'),'-d',classes,
    join(root,'direct-grant-auth-time/src/ch/drivy/identity/DirectGrantAuthTimeAuthenticator.java')]);
  await cp(join(root,'direct-grant-auth-time/resources'),classes,{recursive:true});
  const tests=join(temporary,'tests');await mkdir(tests);
  const classpath=[classes,join(libraries,'*')].join(delimiter);
  await run(javaTool('javac'),['--release','21','-encoding','UTF-8','-g:none','-proc:none','-classpath',classpath,'-d',tests,
    join(root,'direct-grant-auth-time/test/ch/drivy/identity/DirectGrantAuthTimeTest.java')]);
  await run(javaTool('java'),['-classpath',[tests,classpath].join(delimiter),'ch.drivy.identity.DirectGrantAuthTimeTest']);
  await mkdir(dirname(output),{recursive:true});
  await run(javaTool('jar'),['--create','--file',output,'--no-manifest','--date=2026-10-17T00:00:00Z','-C',classes,'.']);
  console.log(`Identity provider compiled for Keycloak ${lock.keycloak.version} (Java 21).`);
} finally {
  const absolute=resolve(temporary);
  if(dirname(absolute)!==resolve(tmpdir())||!basename(absolute).startsWith('drivy-identity-build-'))throw new Error('IDENTITY_BUILD_CLEANUP_TARGET_REFUSED');
  await rm(absolute,{recursive:true,force:true});
}
