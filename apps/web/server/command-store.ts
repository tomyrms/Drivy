import {randomUUID} from 'node:crypto';
import type {Pool,PoolClient} from 'pg';
import {decodeRow,encryptPayload,keyringSchema,ownerSchema,JournalError,type CommandBinding,type CommandKeyring,type CommandOwner,type CommandPayload,type CommandRecord,type CommandRow} from './command-crypto.js';
export type {CommandBinding,CommandKeyring,CommandOwner,CommandPayload,CommandRecord,CommandState} from './command-crypto.js';
export {JournalError} from './command-crypto.js';
export interface CommandStore {
  find(owner:CommandOwner):Promise<CommandRecord|undefined>;
  get(owner:CommandOwner,operationId:string):Promise<CommandRecord|undefined>;
  create(owner:CommandOwner,binding:CommandBinding,payload:CommandPayload):Promise<CommandRecord>;
  review(owner:CommandOwner,record:CommandRecord,sessionHash:string,confirmationHash:string):Promise<CommandRecord>;
  claim(owner:CommandOwner,record:CommandRecord,sessionHash:string,confirmationHash:string):Promise<CommandRecord>;
  submitting(owner:CommandOwner,record:CommandRecord):Promise<CommandRecord>;
  settle(owner:CommandOwner,record:CommandRecord,state:'COMMITTED'|'REJECTED'|'UNCERTAIN'):Promise<CommandRecord>;
  release(owner:CommandOwner,record:CommandRecord):Promise<void>;
  cancel(owner:CommandOwner,record:CommandRecord,sessionHash:string,confirmationHash:string):Promise<void>;
}
const busy=()=>new JournalError('PROFILE_COMMAND_PENDING',409);
export class PostgresCommandStore implements CommandStore {
  private readonly ring:CommandKeyring;
  constructor(private readonly pool:Pool,keyring:CommandKeyring){this.ring=keyringSchema.parse(keyring);}
  private async transaction<T>(owner:CommandOwner,work:(db:PoolClient)=>Promise<T>):Promise<T>{
    ownerSchema.parse(owner);const db=await this.pool.connect();
    try{await db.query('BEGIN');await db.query('SET LOCAL ROLE drivy_web_commands');await db.query("SET LOCAL lock_timeout='3s'");await db.query("SET LOCAL statement_timeout='5s'");
      await db.query("SELECT set_config('web.issuer',$1,true),set_config('web.subject',$2,true)",[owner.issuer,owner.subject]);
      const value=await work(db);await db.query('COMMIT');return value;
    }catch(error){await db.query('ROLLBACK');throw error;}finally{db.release();}
  }
  async find(owner:CommandOwner){return this.transaction(owner,async db=>{const row=(await db.query<CommandRow>(`SELECT * FROM drivy_web.profile_command WHERE state<>'CANCELLED'
    ORDER BY CASE WHEN state IN('PREPARED','SUBMITTED','UNCERTAIN') THEN 0 ELSE 1 END,created_at DESC,operation_id DESC LIMIT 1`)).rows[0];return row?decodeRow(row,this.ring):undefined;});}
  async get(owner:CommandOwner,operationId:string){return this.transaction(owner,async db=>{const row=(await db.query<CommandRow>('SELECT * FROM drivy_web.profile_command WHERE operation_id=$1',[operationId])).rows[0];return row?decodeRow(row,this.ring):undefined;});}
  async create(owner:CommandOwner,binding:CommandBinding,payload:CommandPayload){
    const operationId=randomUUID();const row={operation_id:operationId,issuer:owner.issuer,subject:owner.subject,person_id:binding.personId,school_id:binding.schoolId,
      membership_id:binding.membershipId,access_epoch:binding.accessEpoch,kind:binding.kind,target_id:binding.targetId,expected_version:binding.expectedVersion,key_id:this.ring.activeKeyId};
    const sealed=encryptPayload(row,payload,this.ring);
    try{return await this.transaction(owner,async db=>{const saved=(await db.query<CommandRow>(`INSERT INTO drivy_web.profile_command
      (operation_id,issuer,subject,person_id,school_id,membership_id,access_epoch,kind,target_id,expected_version,key_id,sealed)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`,[operationId,owner.issuer,owner.subject,binding.personId,binding.schoolId,binding.membershipId,binding.accessEpoch,binding.kind,binding.targetId,binding.expectedVersion,row.key_id,sealed])).rows[0]!;return decodeRow(saved,this.ring);});}
    catch(error){if(typeof error==='object'&&error!==null&&'code'in error&&error.code==='23505')throw busy();throw error;}
  }
  async review(owner:CommandOwner,record:CommandRecord,sessionHash:string,confirmationHash:string){return this.transaction(owner,async db=>{
    const row=(await db.query<CommandRow>(`UPDATE drivy_web.profile_command SET review_hash=$3,review_session_hash=$4,revision=revision+1,
      state=CASE WHEN state='SUBMITTED' THEN 'UNCERTAIN' ELSE state END,lease_id=NULL,lease_until=NULL,updated_at=clock_timestamp()
      WHERE operation_id=$1 AND revision=$2 AND state<>'CANCELLED' AND (lease_until IS NULL OR lease_until<clock_timestamp()) RETURNING *`,
      [record.operationId,record.revision,confirmationHash,sessionHash])).rows[0];if(!row)throw busy();return decodeRow(row,this.ring);
  });}
  async claim(owner:CommandOwner,record:CommandRecord,sessionHash:string,confirmationHash:string){return this.transaction(owner,async db=>{
    const row=(await db.query<CommandRow>(`UPDATE drivy_web.profile_command SET lease_id=$5,lease_until=clock_timestamp()+interval '90 seconds',revision=revision+1,updated_at=clock_timestamp()
      WHERE operation_id=$1 AND revision=$2 AND review_hash=$3 AND review_session_hash=$4 AND state<>'CANCELLED'
      AND (lease_until IS NULL OR lease_until<clock_timestamp()) RETURNING *`,[record.operationId,record.revision,confirmationHash,sessionHash,randomUUID()])).rows[0];
    if(!row)throw new JournalError('PROFILE_CONFIRMATION_CHANGED',409);return decodeRow(row,this.ring);
  });}
  async submitting(owner:CommandOwner,record:CommandRecord){return this.transaction(owner,async db=>{
    const row=(await db.query<CommandRow>(`UPDATE drivy_web.profile_command SET state='SUBMITTED',finished_at=NULL,lease_until=clock_timestamp()+interval '90 seconds',revision=revision+1,updated_at=clock_timestamp()
      WHERE operation_id=$1 AND revision=$2 AND lease_id=$3 AND lease_until>clock_timestamp() RETURNING *`,[record.operationId,record.revision,record.leaseId])).rows[0];
    if(!row)throw busy();return decodeRow(row,this.ring);
  });}
  async settle(owner:CommandOwner,record:CommandRecord,state:'COMMITTED'|'REJECTED'|'UNCERTAIN'){return this.transaction(owner,async db=>{
    const row=(await db.query<CommandRow>(`UPDATE drivy_web.profile_command SET state=$4,finished_at=CASE WHEN $4 IN('COMMITTED','REJECTED') THEN clock_timestamp() ELSE NULL END,
      lease_id=NULL,lease_until=NULL,revision=revision+1,updated_at=clock_timestamp() WHERE operation_id=$1 AND revision=$2 AND lease_id=$3 RETURNING *`,
      [record.operationId,record.revision,record.leaseId,state])).rows[0];if(!row)throw busy();return decodeRow(row,this.ring);
  });}
  async release(owner:CommandOwner,record:CommandRecord){if(!record.leaseId)return;await this.transaction(owner,async db=>{await db.query(`UPDATE drivy_web.profile_command
    SET state=CASE WHEN state='SUBMITTED' THEN 'UNCERTAIN' ELSE state END,lease_id=NULL,lease_until=NULL,revision=revision+1,updated_at=clock_timestamp()
    WHERE operation_id=$1 AND lease_id=$2`,[record.operationId,record.leaseId]);});}
  async cancel(owner:CommandOwner,record:CommandRecord,sessionHash:string,confirmationHash:string){await this.transaction(owner,async db=>{
    const saved=await db.query(`UPDATE drivy_web.profile_command SET state='CANCELLED',finished_at=clock_timestamp(),lease_id=NULL,lease_until=NULL,revision=revision+1,updated_at=clock_timestamp()
      WHERE operation_id=$1 AND revision=$2 AND review_hash=$3 AND review_session_hash=$4 AND state IN('PREPARED','REJECTED')
      AND (lease_until IS NULL OR lease_until<clock_timestamp())`,[record.operationId,record.revision,confirmationHash,sessionHash]);if(!saved.rowCount)throw busy();
  });}
}
export class UnavailableCommandStore implements CommandStore {
  private failed():never{throw new JournalError('COMMAND_STORAGE_UNAVAILABLE');}
  async find():Promise<never>{return this.failed();}async get():Promise<never>{return this.failed();}async create():Promise<never>{return this.failed();}
  async review():Promise<never>{return this.failed();}async claim():Promise<never>{return this.failed();}async submitting():Promise<never>{return this.failed();}
  async settle():Promise<never>{return this.failed();}async release():Promise<never>{return this.failed();}async cancel():Promise<never>{return this.failed();}
}
