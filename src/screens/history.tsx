import { Pressable, View } from 'react-native';
import { router } from 'expo-router';
import { useStore } from '@/data/store';
import { formatDay, historyOrder, tripCounts } from '@/lib/logic';
import { Button, Card, Page, styles, Txt } from '@/components/ui';
import { ItemText } from './trip';

export function HistoryList() {
  const { state } = useStore();
  return <Page>
    <View style={{ alignItems: 'flex-start' }}><Button onPress={() => { if (router.canGoBack()) router.back(); else router.replace('/'); }}>← Ostoslista</Button></View>
    <Txt title>Aiemmat ostosreissut</Txt>
    {!state.history.length ? <Card>
      <Txt style={styles.subtitle}>Ei vielä aiempia</Txt>
      <Txt muted>Kun painat ostoslistalla ”Valmis”, lista tallentuu tänne.</Txt>
    </Card> : state.history.map(trip => <Pressable accessibilityRole="button" key={trip.id}
      onPress={() => router.push({ pathname: '/aiemmat/[id]', params: { id: trip.id } })}>
      <Card>
        <Txt style={styles.subtitle}>{formatDay(trip.archivedAt)}</Txt>
        <Txt muted small>{trip.meals.length ? trip.meals.join(', ') : 'Ei ruokia'} · {tripCounts(trip.items, trip.extras).toBuy} tuotetta</Txt>
      </Card>
    </Pressable>)}
  </Page>;
}

export function HistoryTrip({ id }: { id: string }) {
  const { state } = useStore();
  const trip = state.history.find(t => t.id === id);
  return <Page>
    <View style={{ alignItems: 'flex-start' }}><Button onPress={() => { if (router.canGoBack()) router.back(); else router.replace('/aiemmat'); }}>← Aiemmat</Button></View>
    {!trip ? <Txt>Ostoslistaa ei löytynyt.</Txt> : <>
      <Txt title>Ostosreissu {formatDay(trip.archivedAt)}</Txt>
      {trip.meals.length > 0 && <Txt muted>Ruoat: {trip.meals.join(', ')}</Txt>}
      {trip.items.length + trip.extras.length === 0 ? <Txt muted>Listalla ei ollut tuotteita.</Txt> : <Card>
        {historyOrder([...trip.items, ...trip.extras]).map((item, index) => <View key={index} style={styles.row}>
          <Txt style={{ width: 24 }}>{item.have ? '🏠' : item.checked ? '✓' : ''}</Txt>
          <View style={styles.grow}><ItemText item={item} /></View>
        </View>)}
      </Card>}
    </>}
  </Page>;
}
