import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { emptyState, saveDish, deleteDish, addMeal, removeMeal, readTrip, updateItem, addExtra, updateExtra, removeExtra, archiveTrip, decodeState } from '../src/data/state.ts';
const dish={id:'dish',name:'Puuro',ingredients:[{name:'kaura',amount:2,unit:'dl'}]};
const setup=()=>addMeal(saveDish(emptyState(1),dish),'dish','meal');
const key='["kaura","dl"]';
describe('local state',()=>{
 it('adds and removes repeated meals, sums amounts',()=>{const s=setup();const next=addMeal(s,'dish','second');assert.equal(readTrip(next).items[0].amount,4);assert.equal(readTrip(removeMeal(next,'second')).items[0].amount,2);assert.equal(readTrip(s).items[0].amount,2);assert.equal(addMeal(s,'missing'),s);});
 it('check/have are mutually exclusive for generated and extra',()=>{let s=updateItem(setup(),key,{checked:true});s=updateItem(s,key,{have:true});assert.equal(readTrip(s).items[0].checked,false);assert.equal(readTrip(s).items[0].have,true);s=updateItem(s,key,{checked:true});assert.equal(readTrip(s).items[0].have,false);s=updateItem(s,key,{checked:false});assert.deepEqual(s.trip.items,{});s=addExtra(s,'kahvi','e');s=updateExtra(s,'e',{checked:true,have:true});assert.deepEqual(s.trip.extras[0],{id:'e',name:'kahvi',checked:false,have:true});s=updateExtra(s,'e',{checked:true});assert.equal(s.trip.extras[0].have,false);s=removeExtra(s,'e');assert.equal(s.trip.extras.length,0);});
 it('edit, reset, remove, restore and default-state cleanup',()=>{let s=updateItem(setup(),key,{amount:3});s=addMeal(s,'dish','2');assert.equal(readTrip(s).items[0].amount,3);assert.equal(readTrip(s).items[0].recipeAmount,4);s=updateItem(s,key,{resetAmount:true});assert.equal(readTrip(s).items[0].amount,4);assert.deepEqual(s.trip.items,{});s=updateItem(s,key,{have:true});s=updateItem(s,key,{removed:true});assert.equal(readTrip(s).items.length,0);assert.equal(readTrip(s).removed[0].have,false);s=updateItem(s,key,{removed:false});assert.equal(readTrip(s).items.length,1);assert.deepEqual(s.trip.items,{});s=updateItem(s,key,{amount:null});assert.equal(readTrip(s).items[0].amount,null);assert.throws(()=>updateItem(s,key,{amount:0}));});
 it('drops stale state when meals or recipe ingredients disappear',()=>{let s=updateItem(setup(),key,{checked:true});s=removeMeal(s,'meal');assert.deepEqual(s.trip.items,{});s=addMeal(s,'dish','2');assert.equal(readTrip(s).items[0].checked,false);s=updateItem(s,key,{checked:true});s=saveDish(s,{...dish,ingredients:[]});assert.deepEqual(s.trip.items,{});});
 it('deleting a dish removes its meals; history is unaffected',()=>{let s=archiveTrip(setup(),10,'old');s=addMeal(s,'dish','new');s=deleteDish(s,'dish');assert.equal(s.dishes.length,0);assert.equal(s.trip.meals.length,0);assert.deepEqual(s.history[0].meals,['Puuro']);});
 it('archives a snapshot without removed items, starts empty, caps history at 200',()=>{let s=setup();s=addExtra(s,' kahvi ','e');s=updateExtra(s,'e',{have:true});s=updateItem(s,key,{amount:3,checked:true});s=archiveTrip(s,10,'archive');assert.deepEqual(s.history[0],{id:'archive',createdAt:1,archivedAt:10,meals:['Puuro'],items:[{name:'kaura',unit:'dl',amount:3,checked:true,have:false}],extras:[{name:'kahvi',checked:false,have:true}]});assert.equal(s.trip.createdAt,10);assert.deepEqual(s.trip.meals,[]);assert.deepEqual(s.trip.items,{});assert.deepEqual(s.trip.extras,[]);s=saveDish(s,{...dish,name:'Changed'});assert.equal(s.history[0].meals[0],'Puuro');for(let n=11;n<215;n++){s=addExtra(s,'x',`e${n}`);s=archiveTrip(s,n,`h${n}`);}assert.equal(s.history.length,200);assert.equal(s.history[0].archivedAt,214);assert.equal(s.history.at(-1).archivedAt,15);let removed=updateItem(setup(),key,{removed:true});removed=archiveTrip(removed,2,'r');assert.deepEqual(removed.history[0].items,[]);});
 it('refuses empty archive and enforces meal/extra limits',()=>{assert.throws(()=>archiveTrip(emptyState()),/Lista on tyhjä/);let s=emptyState();for(let i=0;i<200;i++)s=addExtra(s,'x',String(i));assert.throws(()=>addExtra(s,'x'),/Enintään 200/);assert.throws(()=>addExtra(emptyState(),'x'.repeat(101)),/Nimi on liian pitkä/);assert.throws(()=>addExtra(emptyState(),'  '),/Anna tuotteelle nimi/);s=saveDish(emptyState(),dish);for(let i=0;i<100;i++)s=addMeal(s,'dish',String(i));assert.throws(()=>addMeal(s,'dish'),/Enintään 100/);});
 it('round trips JSON, missing/broken documents become empty',()=>{const s=setup();assert.deepEqual(decodeState(JSON.stringify(s)),{state:s,unreadableRaw:null});for(const raw of [null,'','{broken','{}','null','{"version":2}'])assert.deepEqual(decodeState(raw).state.dishes,[]);});
});

describe('document recovery', () => {
  it('does not request a backup on first launch or for a valid document', () => {
    assert.equal(decodeState(null).unreadableRaw, null);
    assert.equal(decodeState(JSON.stringify(setup())).unreadableRaw, null);
  });
  it('preserves the exact raw string for parse, shape and normalization failures', () => {
    const cannotNormalize = setup();
    cannotNormalize.trip.items[key] = null;
    for (const raw of ['', '  {broken\n', '{}', 'null', '{"version":2}', JSON.stringify(cannotNormalize)]) {
      const decoded = decodeState(raw);
      assert.equal(decoded.unreadableRaw, raw);
      assert.deepEqual(decoded.state.dishes, []);
      assert.deepEqual(decoded.state.trip.items, {});
    }
  });
});
