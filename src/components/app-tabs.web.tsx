import type { ComponentProps } from 'react';
import { Tabs, TabList, TabTrigger, TabSlot, type TabTriggerSlotProps } from 'expo-router/ui';
import { Pressable, Text, View } from 'react-native';
import { useTheme } from '@/hooks/use-theme';

function TabButton({ children, isFocused, ref, ...props }: TabTriggerSlotProps) {
  const colors = useTheme();
  return <Pressable {...props} ref={ref as ComponentProps<typeof Pressable>['ref']}
    style={{ flex: 1, alignItems: 'center', padding: 10, minHeight: 64 }}>
    <Text style={{ color: isFocused ? colors.accent : colors.muted, fontWeight: '600', fontSize: 13, textAlign: 'center' }}>
      {children}
    </Text>
  </Pressable>;
}

export default function AppTabs() {
  const colors = useTheme();
  return <Tabs style={{ flex: 1, backgroundColor: colors.background }}>
    <TabSlot style={{ flex: 1 }} />
    <TabList asChild>
      <View style={{ flexDirection: 'row', backgroundColor: colors.surface, borderTopWidth: 1, borderColor: colors.border, paddingBottom: 8 }}>
        <TabTrigger name="ostoslista" href="/" asChild>
          <TabButton>{'🛒\nOstoslista'}</TabButton>
        </TabTrigger>
        <TabTrigger name="ruokalajit" href="/ruokalajit" asChild>
          <TabButton>{'🍲\nRuokalajit'}</TabButton>
        </TabTrigger>
      </View>
    </TabList>
  </Tabs>;
}
