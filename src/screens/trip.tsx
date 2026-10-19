import { useEffect, useState } from 'react';
import { Pressable, View } from 'react-native';
import { router } from 'expo-router';
import { useStore } from '@/data/store';
import { readTrip, type ItemPatch } from '@/data/state';
import { fold, formatAmount, parseAmount, statusText, tripCounts, uncheckedFirst } from '@/lib/logic';
import type { Extra, ShopItem } from '@/lib/model';
import { useTheme } from '@/hooks/use-theme';
import { Button, Card, Collapse, Input, Page, Sheet, styles, SuggestInput, Txt } from '@/components/ui';
export function ItemText({ item }: { item: { name: string; amount?: number | null; unit?: string; checked?: boolean } }) {
  const quantity = [item.amount != null ? formatAmount(item.amount) : '', item.unit].filter(Boolean).join(' ');
  return <Txt muted={!!item.checked} style={item.checked ? styles.checked : undefined}>
    {quantity ? <Txt muted={!!item.checked} style={{ fontWeight: item.checked ? '400' : '600' }}>{quantity} </Txt> : null}{item.name}
  </Txt>;
}

function ItemSheet({ item, onSave, onClose, actionError }: {
  item: ShopItem; onSave: (patch: ItemPatch) => void; onClose: () => void; actionError: string;
}) {
  const [text, setText] = useState(formatAmount(item.amount));
  const [error, setError] = useState('');
  const save = () => {
    const amount = parseAmount(text);
    if (Number.isNaN(amount)) { setError('Määrän pitää olla positiivinen luku, esim. 1,5.'); return; }
    if (item.edited && amount === item.amount) { onClose(); return; }
    onSave({ amount });
  };
  const recipeAmount = item.recipeAmount == null ? 'ei määrää'
    : [formatAmount(item.recipeAmount), item.unit].filter(Boolean).join(' ');
  return <Sheet title={item.name} onClose={onClose}>
    <Txt small>Määrä{item.unit ? ` (${item.unit})` : ''}</Txt>
    <View style={styles.row}>
      <Input accessibilityLabel="Määrä" inputMode="decimal" value={text} placeholder="ei määrää"
        onChangeText={value => { setText(value); setError(''); }} onSubmitEditing={save} style={styles.grow} />
      <Button primary onPress={save}>Tallenna</Button>
    </View>
    {!!(error || actionError) && <Txt error>{error || actionError}</Txt>}
    <Txt muted small>Reseptien mukaan: {recipeAmount} ({item.dishes.join(', ')})</Txt>
    {item.edited && <Button onPress={() => onSave({ resetAmount: true })}>Palauta reseptien määrä</Button>}
    <Button danger onPress={() => onSave({ removed: true })}>Poista listalta</Button>
  </Sheet>;
}

function DishPicker({ onPick, onClose, error }: {
  onPick: (id: string) => void; onClose: () => void; error: string;
}) {
  const { state } = useStore();
  const [query, setQuery] = useState('');
  const colors = useTheme();
  const shown = state.dishes.filter(d => fold(d.name).includes(fold(query.trim())));
  return <Sheet title="Lisää ruoka" onClose={onClose}>
    {!!error && <Txt error>{error}</Txt>}
    {!state.dishes.length ? <>
      <Txt muted>Ei vielä ruokalajeja. Lisää ensin perheen suosikit.</Txt>
      <Button primary onPress={() => { onClose(); router.push('/ruokalajit/uusi'); }}>Lisää ruokalaji</Button>
    </> : <>
      {state.dishes.length > 6 && <Input accessibilityLabel="Hae ruokalajia" placeholder="Hae ruokalajia" value={query} onChangeText={setQuery} />}
      {shown.map(d => <Pressable key={d.id} accessibilityRole="button" accessibilityLabel={d.name}
        onPress={() => onPick(d.id)}
        style={({ pressed }) => ({ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
          gap: 12, paddingVertical: 14, paddingHorizontal: 16, borderWidth: 1, borderColor: colors.border,
          borderRadius: 10, backgroundColor: colors.background, opacity: pressed ? .7 : 1 })}>
        <Txt style={{ flex: 1 }}>{d.name}</Txt><Txt>+</Txt>
      </Pressable>)}
      {!shown.length && <Txt muted>Ei osumia.</Txt>}
    </>}
  </Sheet>;
}

type Toast = { kind: 'items' | 'extras'; id: string; name: string };
export default function TripView() {  
  const store = useStore();
  const trip = readTrip(store.state);
  const c = useTheme();
  const [picking, setPicking] = useState(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [confirm, setConfirm] = useState(false);
  const [newExtra, setNewExtra] = useState('');
  const [error, setError] = useState('');
  const [toast, setToast] = useState<Toast | null>(null);
  useEffect(() => { if (!toast) return; const timer = setTimeout(() => setToast(null), 6000); return () => clearTimeout(timer); }, [toast]);
  const act = (fn: () => void) => { try { fn(); setError(''); return true; } catch (e) { setError((e as Error).message); return false; } };
  const toggle = (kind: 'items' | 'extras', item: ShopItem | Extra, field: 'checked' | 'have' = 'checked') => { const id = 'key' in item ? item.key : item.id; const value = !item[field]; if (act(() => kind === 'items' ? store.updateItem(id, { [field]: value }) : store.updateExtra(id, { [field]: value }))) { if (field === 'have' && value) setToast({ kind, id, name: item.name }); else if (toast?.id === id) setToast(null); } };
  const rows = (list: (ShopItem | Extra)[], kind: 'items' | 'extras') =>
    <Card style={{ paddingVertical: 0 }}>{uncheckedFirst(list).map(item => {      
const id = 'key' in item ? item.key : item.id; return <View key={id} style={[styles.item, { borderColor: c.border }]}>
        <Pressable accessibilityRole="checkbox" accessibilityLabel={item.name} accessibilityState={{ checked: item.checked }} onPress={() => toggle(kind, item)} style={styles.itemLabel}>
          <View style={{ width: 22, height: 22, borderRadius: 5, borderWidth: 1, borderColor: item.checked ? c.accent : c.muted, backgroundColor: item.checked ? c.accent : 'transparent', alignItems: 'center', justifyContent: 'center' }}>
            <Txt style={{ color: '#fff', fontSize: 16 }}>{item.checked ? '✓' : ''}</Txt>
          </View>
          <View style={styles.grow}>
            <ItemText item={item} />{'dishes' in item && <Txt muted small style={{ fontSize: 12 }}>{item.edited ? 'Muokattu · ' : ''}{item.dishes.join(', ')}</Txt>}</View>
        </Pressable>{!item.checked && <Button label={`On jo: ${item.name}`} onPress={() => toggle(kind, item, 'have')}>On jo</Button>}<Pressable accessibilityRole="button" accessibilityLabel={`${kind === 'items' ? 'Muokkaa' : 'Poista'} ${item.name}`} onPress={() => kind === 'items' ? setEditing(id) : act(() => store.removeExtra(id))} style={{ width: 40, minHeight: 44, alignItems: 'center', justifyContent: 'center' }}>
          <Txt muted>{kind === 'items' ? '✎' : '×'}</Txt>
        </Pressable>
      </View>;    
})}</Card>;
  const atHome = [...trip.items.filter(i => i.have).map(item => ({ kind: 'items' as const, item, id: item.key })), ...trip.extras.filter(i => i.have).map(item => ({ kind: 'extras' as const, item, id: item.id }))];
  const editItem = trip.items.find(i => i.key === editing); const status = statusText(tripCounts(trip.items, trip.extras));
  return <Page root overlay={toast && <View accessibilityLiveRegion="polite" style={[styles.toast, { backgroundColor: c.surface, borderColor: c.border }]}>
    <View style={styles.grow}>
      <Txt small>”{toast.name}” on jo kotona.</Txt>
    </View>
    <Button onPress={() => { act(() => toast.kind === 'items' ? store.updateItem(toast.id, { have: false }) : store.updateExtra(toast.id, { have: false })); setToast(null); }}>Kumoa</Button>
  </View>}>
    <View style={styles.between}>
      <Txt title>Ostoslista</Txt>
      <Button onPress={() => router.push('/aiemmat')}>Aiemmat</Button>
    </View>{!!error && <Txt error>{error}</Txt>}<Card>
      <Txt style={styles.subtitle}>Ruoat{trip.meals.length ? ` · ${trip.meals.length}` : ''}</Txt>{!trip.meals.length ? <Txt muted small>Lisää ruoat, joihin ostat ainekset. Niiden ainekset kootaan listaksi.</Txt> : trip.meals.map(m =>
        <View key={m.id} style={styles.between}>
          <View style={styles.grow}>
            <Txt style={{ fontWeight: '600' }}>{m.name}</Txt>
          </View>
          <Button label={`Poista ${m.name}`} onPress={() => { act(() => store.removeMeal(m.id)); setToast(null); }}>×</Button>
        </View>)}<View style={{ alignItems: 'flex-start' }}>
        <Button primary onPress={() => { setError(''); setPicking(true); }}>+ Lisää ruoka</Button>
      </View>
    </Card>{status && <Txt muted small style={{ textAlign: 'center' }}>{status}</Txt>}{trip.items.some(i => !i.have) && rows(trip.items.filter(i => !i.have), 'items')}{trip.removed.length > 0 && <Collapse label={`Poistetut (${trip.removed.length})`}>
      <Card>{trip.removed.map(item =>
        <View key={item.key} style={styles.row}>
          <View style={styles.grow}>
            <ItemText item={item} />
          </View>
          <Button onPress={() => act(() => store.updateItem(item.key, { removed: false }))}>Palauta</Button>
        </View>)}</Card>
    </Collapse>}<Txt style={[styles.subtitle, { marginTop: 8 }]}>Muut ostokset</Txt>
    <View style={{ ...styles.row, alignItems: 'flex-start' }}>
      <View style={styles.grow}>
        <SuggestInput accessibilityLabel="Uusi tuote" placeholder="esim. kahvi, vessapaperi" maxLength={100} value={newExtra} onChangeText={setNewExtra} onPick={s => setNewExtra(s.name)} onSubmitEditing={() => { if (act(() => store.addExtra(newExtra))) setNewExtra(''); }} />
      </View>
      <Button primary disabled={!newExtra.trim()} onPress={() => { if (act(() => store.addExtra(newExtra))) setNewExtra(''); }}>Lisää</Button>
    </View>{trip.extras.some(i => !i.have) && rows(trip.extras.filter(i => !i.have), 'extras')}{atHome.length > 0 && <Collapse label={`Kotona (${atHome.length})`}>
      <Card>{atHome.map(({ item, kind, id }) =>
        <View key={kind + id} style={styles.row}>
          <View style={styles.grow}>
            <ItemText item={item} />
          </View>
          <Button onPress={() => toggle(kind, item, 'have')}>Ostettava</Button>
        </View>)}</Card>
    </Collapse>}{(trip.meals.length > 0 || trip.extras.length > 0) && (confirm ? <Card>
      <Txt>Merkitäänkö ostosreissu valmiiksi? Lista siirtyy aiempiin ja aloitetaan uusi, tyhjä lista.</Txt>
      <View style={styles.row}>
        <Button onPress={() => setConfirm(false)}>Peruuta</Button>
        <Button primary onPress={() => { if (act(store.archiveTrip)) { setConfirm(false); setToast(null); setEditing(null); } }}>Valmis</Button>
      </View>
    </Card> : <Button onPress={() => setConfirm(true)}>✓ Valmis – aloita uusi lista</Button>)}{picking && <DishPicker error={error} onClose={() => setPicking(false)} onPick={id => { if (act(() => store.addMeal(id))) { setPicking(false); setToast(null); } }} />}{editItem && <ItemSheet actionError={error} key={editItem.key} item={editItem} onClose={() => setEditing(null)} onSave={p => { if (act(() => store.updateItem(editItem.key, p))) { setEditing(null); setToast(null); } }} />}</Page>;
}
