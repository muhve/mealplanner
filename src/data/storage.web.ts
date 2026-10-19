export const loadDocument=()=>typeof localStorage==='undefined'?null:localStorage.getItem('ruokalista-v1');
export const saveDocument=(value:string)=>localStorage.setItem('ruokalista-v1',value);

export function backupDocument(raw: string) {
  let timestamp = Date.now();
  // Retain both backups even if two recovery attempts happen in the same millisecond.
  while (localStorage.getItem(`ruokalista-v1-backup-${timestamp}`) !== null) timestamp++;
  localStorage.setItem(`ruokalista-v1-backup-${timestamp}`, raw);
}
