import Storage from 'expo-sqlite/kv-store';
export const loadDocument=()=>Storage.getItemSync('ruokalista-v1');
export const saveDocument=(value:string)=>Storage.setItemSync('ruokalista-v1',value);

export function backupDocument(raw: string) {
  let timestamp = Date.now();
  // Retain both backups even if two recovery attempts happen in the same millisecond.
  while (Storage.getItemSync(`ruokalista-v1-backup-${timestamp}`) !== null) timestamp++;
  Storage.setItemSync(`ruokalista-v1-backup-${timestamp}`, raw);
}
