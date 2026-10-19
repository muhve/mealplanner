import { useEffect, useRef, useState, type ComponentRef } from 'react';
import { Pressable, TextInput, View } from 'react-native';
import { router } from 'expo-router';
import { useStore } from '@/data/store';
import { newId } from '@/data/state';
import { fold, formatAmount, ingredientSummary, toDishBody, type FormRow } from '@/lib/logic';
import { Button, Card, Input, Page, styles, SuggestInput, Txt } from '@/components/ui';

export function DishList() {
  const { state } = useStore();
  const [query, setQuery] = useState('');
  const q = fold(query.trim());
  const shown = state.dishes.filter(d => fold(d.name).includes(q) || d.ingredients.some(i => fold(i.name).includes(q)));
  const create = () => router.push('/ruokalajit/uusi');
  return <Page root>
    <View style={styles.between}>
      <Txt title>Ruokalajit</Txt><Button primary onPress={create}>+ Uusi</Button>
    </View>
    {!state.dishes.length ? <Card>
      <Txt style={styles.subtitle}>Ei vielä ruokalajeja</Txt>
      <Txt muted>Tallenna perheen suosikit ainesosineen, niin ostoslistan teko käy nopeasti.</Txt>
      <Button primary onPress={create}>Lisää ensimmäinen ruokalaji</Button>
    </Card> : <>
      <Input accessibilityLabel="Hae ruokalajeja" placeholder="Hae nimellä tai ainesosalla" value={query} onChangeText={setQuery} />
      {!shown.length && <Txt muted>Ei osumia haulle ”{query.trim()}”.</Txt>}
      {shown.map(d => <Pressable accessibilityRole="button" key={d.id}
        onPress={() => router.push({ pathname: '/ruokalajit/[id]', params: { id: d.id } })}>
        <Card>
          <Txt style={styles.subtitle}>{d.name}</Txt>
          <Txt muted small>{d.ingredients.length ? ingredientSummary(d.ingredients) : 'Ei ainesosia'}</Txt>
        </Card>
      </Pressable>)}
    </>}
  </Page>;
}

const blank = () => ({ key: newId(), name: '', amount: '', unit: '' });

export function DishForm({ id }: { id?: string }) {
  const { state, saveDish, deleteDish } = useStore();
  const dish = state.dishes.find(d => d.id === id);
  const [name, setName] = useState(dish?.name ?? '');
  const [rows, setRows] = useState(() => [
    ...(dish?.ingredients.map(i => ({ ...i, key: newId(), amount: formatAmount(i.amount) })) ?? []), blank(),
  ]);
  const [error, setError] = useState('');
  const [confirm, setConfirm] = useState(false);
  const [activeRow, setActiveRow] = useState<string | null>(null);
  const inputs = useRef(new Map<string, ComponentRef<typeof TextInput>>());
  const focusKey = useRef<string | null>(null);
  useEffect(() => {
    if (focusKey.current) {
      inputs.current.get(focusKey.current)?.focus();
      focusKey.current = null;
    }
  });

  const update = (key: string, field: keyof FormRow, value: string) =>
    setRows(rs => rs.map(r => r.key === key ? { ...r, [field]: value } : r));
  const leave = () => {
    if (router.canGoBack()) router.back();
    else router.replace('/ruokalajit');
  };
  const addRow = () => {
    if (rows.length >= 100) return;
    const row = blank();
    focusKey.current = row.key;
    setRows(rs => [...rs, row]);
  };
  const nextRow = (index: number) => {
    if (index === rows.length - 1) addRow();
    else inputs.current.get(rows[index + 1].key)?.focus();
  };
  const save = () => {
    const result = toDishBody(name, rows);
    if (result.error) { setError(result.error); return; }
    try { saveDish({ id: id ?? newId(), ...result.body! }); leave(); }
    catch (e) { setError((e as Error).message); }
  };

  if (id && !dish) return <Page>
    <Button onPress={leave}>← Ruokalajit</Button><Txt>Ruokalajia ei löytynyt.</Txt>
  </Page>;

  return <Page>
    <View style={{ alignItems: 'flex-start' }}><Button onPress={leave}>← Ruokalajit</Button></View>
    <Txt title>{id ? 'Muokkaa ruokalajia' : 'Uusi ruokalaji'}</Txt>
    <Txt small>Nimi</Txt>
    <Input accessibilityLabel="Nimi" value={name} onChangeText={setName} maxLength={100} placeholder="esim. Lohikeitto" autoFocus={!id} />
    <Txt style={styles.subtitle}>Ainesosat</Txt>
    {rows.map((row, i) => <View key={row.key}
      style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 6, zIndex: activeRow === row.key ? 1 : 0 }}>
      <View style={{ flex: 1, minWidth: 0 }}>
        <SuggestInput floatingSuggestions
          ref={input => { if (input) inputs.current.set(row.key, input); else inputs.current.delete(row.key); }}
          accessibilityLabel={`Ainesosa ${i + 1}`} placeholder="Ainesosa" maxLength={100}
          value={row.name} onChangeText={value => update(row.key, 'name', value)}
          style={{ paddingHorizontal: 10 }} onFocus={() => setActiveRow(row.key)}
          returnKeyType="next" onSubmitEditing={() => nextRow(i)}
          onPick={s => setRows(rs => rs.map(r => r.key === row.key
            ? { ...r, name: s.name, unit: r.unit.trim() ? r.unit : s.unit } : r))} />
      </View>
      <Input accessibilityLabel={`Määrä ${i + 1}`} placeholder="Määrä" inputMode="decimal"
        value={row.amount} maxLength={12} onChangeText={v => update(row.key, 'amount', v)}
        returnKeyType="next" onSubmitEditing={() => nextRow(i)}
        style={{ width: 72, paddingHorizontal: 10 }} onFocus={() => setActiveRow(row.key)} />
      <View style={{ width: 68 }}>
        <SuggestInput units floatingSuggestions accessibilityLabel={`Yksikkö ${i + 1}`} placeholder="Yks." maxLength={20}
          value={row.unit} onChangeText={v => update(row.key, 'unit', v)}
          style={{ paddingHorizontal: 10 }} onFocus={() => setActiveRow(row.key)}
          returnKeyType="next" onSubmitEditing={() => nextRow(i)}
          onPick={s => update(row.key, 'unit', s.name)} />
      </View>
      <Pressable accessibilityRole="button" accessibilityLabel={`Poista ainesosa ${i + 1}`}
        style={{ width: 40, height: 46, alignItems: 'center', justifyContent: 'center' }}
        onPress={() => setRows(rs => rs.length === 1 ? [blank()] : rs.filter(r => r.key !== row.key))}>
        <Txt muted style={{ fontSize: 24 }}>×</Txt>
      </Pressable>
    </View>)}
    <Button disabled={rows.length >= 100} onPress={addRow}>+ Lisää ainesosa</Button>
    {!!error && <Txt error>{error}</Txt>}
    <Button primary onPress={save}>Tallenna</Button>
    {id && (confirm ? <Card>
      <Txt>Poistetaanko ”{name.trim() || 'ruokalaji'}” pysyvästi? Se poistuu myös nykyiseltä ostoslistalta.</Txt>
      <View style={styles.row}>
        <Button onPress={() => setConfirm(false)}>Peruuta</Button>
        <Button primary danger onPress={() => {
          try { deleteDish(id); leave(); } catch (e) { setError((e as Error).message); }
        }}>Poista</Button>
      </View>
    </Card> : <Button danger onPress={() => setConfirm(true)}>Poista ruokalaji</Button>)}
  </Page>;
}
