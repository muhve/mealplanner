export type Ingredient = {
    name: string;
    amount: number | null;
    unit: string;
};
export type Dish = {
    id: string;
    name: string;
    ingredients: Ingredient[];
};
export type ItemState = {
    edited: boolean;
    amount: number | null;
    removed: boolean;
    checked: boolean;
    have: boolean;
};
export type Extra = {
    id: string;
    name: string;
    checked: boolean;
    have: boolean;
};
export type Trip = {
    createdAt: number;
    meals: {
        id: string;
        dishId: string;
    }[];
    items: Record<string, ItemState>;
    extras: Extra[];
};
export type ArchivedTrip = {
    id: string;
    createdAt: number;
    archivedAt: number;
    meals: string[];
    items: (Ingredient & {
        checked: boolean;
        have: boolean;
    })[];
    extras: Omit<Extra, 'id'>[];
};
export type AppState = {
    version: 1;
    dishes: Dish[];
    trip: Trip;
    history: ArchivedTrip[];
};
export type Generated = Ingredient & {
    key: string;
    dishes: string[];
};
export type ShopItem = Generated & {
    recipeAmount: number | null;
    edited: boolean;
    checked: boolean;
    have: boolean;
};
export type Marks = {
    checked?: boolean;
    have?: boolean;
};
