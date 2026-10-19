import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { View, Text, Pressable } from 'react-native';
import type { AppState, Dish, Marks } from '../lib/model';
import { useTheme } from '../hooks/use-theme';
import * as ops from './state';
import { loadDocument, saveDocument, backupDocument } from './storage';

type Store = {
  state: AppState;
  saveDish: (dish: Dish) => void;
  deleteDish: (id: string) => void;
  addMeal: (dishId: string) => void;
  removeMeal: (id: string) => void;
  updateItem: (key: string, patch: ops.ItemPatch) => void;
  addExtra: (name: string) => void;
  updateExtra: (id: string, patch: Marks) => void;
  removeExtra: (id: string) => void;
  archiveTrip: () => void;
};
const Context = createContext<Store | null>(null);

export function StoreProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AppState | null>(null);
  const [loadError, setLoadError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const current = useRef<AppState | null>(null);
  const colors = useTheme();

  useEffect(() => {
    let active = true;
    Promise.resolve().then(() => {
      if (!active) return;
      try {
        const decoded = ops.decodeState(loadDocument());
        // Do not publish the empty fallback until the original has been safely copied.
        // A failed backup keeps the load error screen up, preventing later overwrites.
        if (decoded.unreadableRaw !== null) {
          backupDocument(decoded.unreadableRaw);
          // Complete recovery on disk so the next launch does not back up the same bad document again.
          saveDocument(JSON.stringify(decoded.state));
        }
        const loaded = decoded.state;
        current.current = loaded;
        setState(loaded);
        setLoadError(false);
      } catch {
        setLoadError(true);
      }
    });
    return () => { active = false; };
  }, [attempt]);

  // Write before publishing so a failed device write never looks like a saved change.
  const change = (fn: (state: AppState) => AppState) => {
    const next = fn(current.current!);
    saveDocument(JSON.stringify(next));
    current.current = next;
    setState(next);
  };

  if (!state) return (
    <View style={{ flex: 1, backgroundColor: colors.background, alignItems: 'center', justifyContent: 'center', gap: 16 }}>
      <Text style={{ color: colors.muted }}>{loadError ? 'Tietojen lataaminen epäonnistui.' : 'Ladataan…'}</Text>
      {loadError && <Pressable accessibilityRole="button" onPress={() => setAttempt(n => n + 1)} style={{ padding: 16 }}>
        <Text style={{ color: colors.accent }}>Yritä uudelleen</Text>
      </Pressable>}
    </View>
  );

  return <Context value={{
    state,
    saveDish: dish => change(s => ops.saveDish(s, dish)),
    deleteDish: id => change(s => ops.deleteDish(s, id)),
    addMeal: dishId => change(s => ops.addMeal(s, dishId, ops.newId())),
    removeMeal: id => change(s => ops.removeMeal(s, id)),
    updateItem: (key, patch) => change(s => ops.updateItem(s, key, patch)),
    addExtra: name => change(s => ops.addExtra(s, name, ops.newId())),
    updateExtra: (id, patch) => change(s => ops.updateExtra(s, id, patch)),
    removeExtra: id => change(s => ops.removeExtra(s, id)),
    archiveTrip: () => change(s => ops.archiveTrip(s, Date.now(), ops.newId())),
  }}>{children}</Context>;
}

export function useStore() {
  const store = useContext(Context);
  if (!store) throw Error('Store missing');
  return store;
}
