// Explicit test double only. main.ts never imports this module or enables it via env.
import {randomUUID} from 'node:crypto';
import {JournalError,type CommandStore,type CommandOwner,type CommandRecord,type CommandBinding,type CommandPayload} from './command-store.js';
export class TestMemoryCommandStore implements CommandStore {
  private readonly rows=new Map<string,CommandRecord>();
  private allowed(owner:CommandOwner,row:CommandRecord){return owner.issuer===row.issuer&&owner.subject===row.subject;}
  private current(owner:CommandOwner,row:CommandRecord){const current=this.rows.get(row.operationId);if(!current||!this.allowed(owner,current)||current.revision!==row.revision)throw new JournalError('PROFILE_COMMAND_PENDING',409);return current;}
  private change(row:CommandRecord,patch:Partial<CommandRecord>){const next={...row,...patch,revision:row.revision+1,updatedAt:new Date()};this.rows.set(row.operationId,next);return structuredClone(next);}
  private unlocked(row:CommandRecord){if(row.leaseUntil&&row.leaseUntil.getTime()>Date.now())throw new JournalError('PROFILE_COMMAND_PENDING',409);}
  private confirmed(row:CommandRecord,session:string,confirmation:string){if(row.reviewSessionHash!==session||row.reviewHash!==confirmation)throw new JournalError('PROFILE_CONFIRMATION_CHANGED',409);}
  async find(owner:CommandOwner){const rows=[...this.rows.values()].filter(row=>this.allowed(owner,row)&&row.state!=='CANCELLED').reverse();return structuredClone(rows.find(row=>['PREPARED','SUBMITTED','UNCERTAIN'].includes(row.state))??rows[0]);}
  async get(owner:CommandOwner,id:string){const row=this.rows.get(id);return row&&this.allowed(owner,row)?structuredClone(row):undefined;}
  async create(owner:CommandOwner,binding:CommandBinding,payload:CommandPayload){
    if([...this.rows.values()].some(row=>this.allowed(owner,row)&&['PREPARED','SUBMITTED','UNCERTAIN'].includes(row.state)))throw new JournalError('PROFILE_COMMAND_PENDING',409);
    const row:CommandRecord={...structuredClone(payload),...owner,...binding,operationId:randomUUID(),state:'PREPARED',revision:1,keyId:'test',leaseId:null,leaseUntil:null,
      reviewHash:null,reviewSessionHash:null,createdAt:new Date(),updatedAt:new Date(),finishedAt:null};this.rows.set(row.operationId,row);return structuredClone(row);
  }
  async review(owner:CommandOwner,record:CommandRecord,session:string,confirmation:string){const row=this.current(owner,record);this.unlocked(row);return this.change(row,{reviewHash:confirmation,reviewSessionHash:session,state:row.state==='SUBMITTED'?'UNCERTAIN':row.state,leaseId:null,leaseUntil:null});}
  async claim(owner:CommandOwner,record:CommandRecord,session:string,confirmation:string){const row=this.current(owner,record);this.unlocked(row);this.confirmed(row,session,confirmation);return this.change(row,{leaseId:randomUUID(),leaseUntil:new Date(Date.now()+90_000)});}
  async submitting(owner:CommandOwner,record:CommandRecord){const row=this.current(owner,record);if(!row.leaseId||row.leaseId!==record.leaseId||!row.leaseUntil||row.leaseUntil.getTime()<=Date.now())throw new JournalError('PROFILE_COMMAND_PENDING',409);return this.change(row,{state:'SUBMITTED',finishedAt:null});}
  async settle(owner:CommandOwner,record:CommandRecord,state:'COMMITTED'|'REJECTED'|'UNCERTAIN'){const row=this.current(owner,record);if(!row.leaseId||row.leaseId!==record.leaseId)throw new JournalError('PROFILE_COMMAND_PENDING',409);return this.change(row,{state,finishedAt:state==='UNCERTAIN'?null:new Date(),leaseId:null,leaseUntil:null});}
  async release(owner:CommandOwner,record:CommandRecord){const row=this.rows.get(record.operationId);if(row&&this.allowed(owner,row)&&row.leaseId&&row.leaseId===record.leaseId)this.change(row,{state:row.state==='SUBMITTED'?'UNCERTAIN':row.state,leaseId:null,leaseUntil:null});}
  async cancel(owner:CommandOwner,record:CommandRecord,session:string,confirmation:string){const row=this.current(owner,record);this.unlocked(row);this.confirmed(row,session,confirmation);if(!['PREPARED','REJECTED'].includes(row.state))throw new JournalError('PROFILE_COMMAND_PENDING',409);this.change(row,{state:'CANCELLED',finishedAt:new Date()});}
}
