import { useEffect, useRef, useState, type ReactNode, type Ref, type ComponentRef } from 'react';
import {
  KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
  type StyleProp, type TextInputProps, type TextStyle, type ViewStyle,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '@/hooks/use-theme';
import { suggestIngredients, UNITS, visibleSuggestions } from '@/lib/logic';
import { useStore } from '@/data/store';

export const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  between: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 8 },
  grow: { flex: 1, minWidth: 0 },
  card: { borderWidth: 1, borderRadius: 14, padding: 16, gap: 10 },
  title: { fontSize: 24, lineHeight: 30, fontWeight: '600', letterSpacing: -.3 },
  subtitle: { fontSize: 17, fontWeight: '600' },
  input: { borderWidth: 1, borderRadius: 10, paddingHorizontal: 14, paddingVertical: 12, fontSize: 16, minHeight: 46 },
  checked: { textDecorationLine: 'line-through' },
  item: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 8, borderBottomWidth: 1 },
  itemLabel: { flex: 1, flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 8, minHeight: 44 },
  toast: { position: 'absolute', bottom: 12, left: 16, right: 16, borderWidth: 1, borderRadius: 10, padding: 12, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
});

type TextProps = { children: ReactNode; muted?: boolean; title?: boolean; small?: boolean; error?: boolean; style?: StyleProp<TextStyle> };
export function Txt({ children, muted = false, title = false, small = false, error = false, style }: TextProps) {
  const c = useTheme();
  return <Text accessibilityRole={title ? 'header' : error ? 'alert' : undefined}
    style={[{ color: error ? c.error : muted ? c.muted : c.text, fontSize: small ? 14 : 16, lineHeight: small ? 20 : 23 }, title && styles.title, style]}>
    {children}
  </Text>;
}

type ButtonProps = { children: ReactNode; onPress: () => void; primary?: boolean; danger?: boolean; disabled?: boolean; label?: string };
export function Button({ children, onPress, primary = false, danger = false, disabled = false, label }: ButtonProps) {
  const c = useTheme();
  return <Pressable accessibilityRole="button" accessibilityLabel={label} disabled={disabled} onPress={onPress}
    style={({ pressed }) => ({ borderWidth: primary ? 0 : 1, borderColor: c.border, borderRadius: primary ? 10 : 999,
      paddingHorizontal: 14, paddingVertical: 10, minHeight: 44, justifyContent: 'center',
      backgroundColor: primary ? (danger ? c.error : c.accent) : 'transparent', opacity: disabled ? .45 : pressed ? .7 : 1 })}>
    <Text style={{ fontSize: 15, fontWeight: primary ? '600' : '400', textAlign: 'center', color: primary ? '#fff' : danger ? c.error : c.text }}>{children}</Text>
  </Pressable>;
}

export function Card({ children, style }: { children: ReactNode; style?: ViewStyle }) {
  const c = useTheme();
  return <View style={[styles.card, { backgroundColor: c.surface, borderColor: c.border }, style]}>{children}</View>;
}

type InputProps = TextInputProps & { ref?: Ref<ComponentRef<typeof TextInput>> };
export function Input(props: InputProps) {
  const c = useTheme();
  return <TextInput {...props} placeholderTextColor={c.muted}
    style={[styles.input, { color: c.text, backgroundColor: c.background, borderColor: c.border }, props.style]} />;
}

export function Page({ children, root = false, overlay }: { children: ReactNode; root?: boolean; overlay?: ReactNode }) {
  const c = useTheme();
  return <SafeAreaView edges={['top', 'left', 'right']} style={{ flex: 1, backgroundColor: c.background }}>
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1 }}>
      <ScrollView keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ padding: 16, paddingBottom: 40, width: '100%', maxWidth: 640, alignSelf: 'center', gap: 16 }}>
        {root && <Txt title style={{ fontSize: 22, marginBottom: 8 }}>🥕 Ruokalista</Txt>}
        {children}
      </ScrollView>
      {overlay}
    </KeyboardAvoidingView>
  </SafeAreaView>;
}

export function Sheet({ children, title, onClose }: { children: ReactNode; title: string; onClose: () => void }) {
  const c = useTheme();
  const insets = useSafeAreaInsets();
  return <Modal transparent animationType="slide" onRequestClose={onClose}>
    <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={{ flex: 1, justifyContent: 'flex-end', backgroundColor: '#0006' }}>
      <Pressable accessibilityRole="button" accessibilityLabel="Sulje" onPress={onClose} style={StyleSheet.absoluteFill} />
      <View accessibilityViewIsModal style={{ maxHeight: '80%', width: '100%', maxWidth: 640, alignSelf: 'center',
        borderTopLeftRadius: 18, borderTopRightRadius: 18, backgroundColor: c.surface, padding: 16, paddingBottom: 16 + insets.bottom, gap: 12 }}>
        <View style={styles.between}>
          <Txt style={styles.subtitle}>{title}</Txt><Button onPress={onClose}>Sulje</Button>
        </View>
        <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ gap: 12 }}>{children}</ScrollView>
      </View>
    </KeyboardAvoidingView>
  </Modal>;
}

type SuggestProps = InputProps & { onPick: (suggestion: { name: string; unit: string }) => void; units?: boolean; floatingSuggestions?: boolean };
export function SuggestInput({ value = '', onChangeText, onPick, units = false, floatingSuggestions = false, ...props }: SuggestProps) {
  const [focused, setFocused] = useState(false);
  const blurTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const { state } = useStore();
  useEffect(() => () => { if (blurTimer.current) clearTimeout(blurTimer.current); }, []);
  const query = value.trim();
  const items = !focused ? [] : units
    ? visibleSuggestions({ query, items: UNITS.filter(u => u.includes(query)).map(name => ({ name, unit: '' })) }, query)
    : query ? visibleSuggestions({ query, items: suggestIngredients(state.dishes, query) }, query) : [];
  return <View style={{ gap: 4, zIndex: focused ? 1 : 0 }}>
    <Input {...props} value={value} onChangeText={text => { setFocused(true); onChangeText?.(text); }}
      onFocus={event => { if (blurTimer.current) clearTimeout(blurTimer.current); setFocused(true); props.onFocus?.(event); }}
      // Leave the suggestion mounted until the tap that blurred the input lands.
      onBlur={event => { blurTimer.current = setTimeout(() => setFocused(false), 150); props.onBlur?.(event); }} />
    {focused && items.length > 0 && <Card style={{ padding: 4, ...(floatingSuggestions ? { position: 'absolute', top: '100%', marginTop: 4, minWidth: 240, maxHeight: 240, zIndex: 10, ...(units ? { right: 0 } : { left: 0 }) } : {}) }}>
      <ScrollView keyboardShouldPersistTaps="handled">{items.map(s => <Pressable key={s.name} accessibilityRole="button" onPress={() => { onPick(s); setFocused(false); }}
        style={{ padding: 10, minHeight: 44 }}>
        <Txt>{s.name}{!units && s.unit ? <Txt muted small> · {s.unit}</Txt> : null}</Txt>
      </Pressable>)}</ScrollView>
    </Card>}
  </View>;
}

export function Collapse({ label, children }: { label: string; children: ReactNode }) {
  const [open, setOpen] = useState(false);
  return <View style={{ gap: 8 }}>
    <Pressable accessibilityRole="button" accessibilityState={{ expanded: open }} onPress={() => setOpen(!open)} style={{ paddingVertical: 10 }}>
      <Txt muted small>{open ? '▾' : '▸'} {label}</Txt>
    </Pressable>
    {open && children}
  </View>;
}
