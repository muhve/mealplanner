import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { parseAmount, formatAmount, fold, itemKey, toDishBody, ingredientSummary, visibleSuggestions, tripCounts, statusText, historyOrder, uncheckedFirst, aggregateIngredients, applyItemState, knownIngredients, suggestIngredients, markClause, formatDay, UNITS } from '../src/lib/logic.ts';
const r=(name,amount='',unit='')=>({name,amount,unit});
const mark=(checked,have=false)=>({checked,have});
describe('amounts',()=>{
 it('reads Finnish and English decimals and spaces',()=>{for(const [raw,n] of [['1,5',1.5],[' 2.25 ',2.25],['400',400],[',5',.5],['0,125',.125],['1 000',1000],['1000000',1000000],['0.001',.001]])assert.equal(parseAmount(raw),n);});
 it('empty is no amount',()=>{for(const v of ['', '  ',undefined,null])assert.equal(parseAmount(v),null);});
 it('rejects invalid, zero, negative and excessive decimals',()=>{for(const v of ['abc','0','-1','1,2,3','1e5','2kg','.','1000001','0,0004','0,0000001','1.0000','Infinity'])assert.ok(Number.isNaN(parseAmount(v)),v);});
 it('formats exact Finnish amounts',()=>{for(const [n,s] of [[1.5,'1,5'],[400,'400'],[.001,'0,001'],[null,'']])assert.equal(formatAmount(n),s);});
});
describe('dish form',()=>{
 it('drops blank rows, trims and parses',()=>assert.deepEqual(toDishBody(' Puuro ',[r(' kaura ','2,5',' dl '),r(''),r('suola')]),{body:{name:'Puuro',ingredients:[{name:'kaura',amount:2.5,unit:'dl'},{name:'suola',amount:null,unit:''}]}}));
 it('first bad row uses on-screen number',()=>{assert.equal(toDishBody('X',[r('a'),r(''),r('','2','dl')]).error,'Ainesosa 3: anna nimi.');assert.match(toDishBody('X',[r('a','paljon')]).error,/Ainesosa 1: määrän/);});
 it('collapses whitespace and caps nonblank rows',()=>{assert.equal(toDishBody('Kana  curry',[r('kookos  maito')]).body.name,'Kana curry');assert.equal(toDishBody('X',[r('kookos  maito')]).body.ingredients[0].name,'kookos maito');const many=Array.from({length:101},(_,i)=>r(`a${i}`));assert.equal(toDishBody('X',many).error,'Enintään 100 ainesosaa.');assert.equal(toDishBody('X',[...many.slice(1),r('')]).body.ingredients.length,100);});
 it('requires name first, and enforces text limits',()=>{assert.equal(toDishBody('  ',[r('a','x')]).error,'Anna ruokalajille nimi.');assert.ok(toDishBody('a'.repeat(101),[]).error);assert.ok(toDishBody('X',[r('a'.repeat(101))]).error);assert.ok(toDishBody('X',[r('a','','u'.repeat(21))]).error);assert.ok(toDishBody('X',[r('a'.repeat(100),'','u'.repeat(20))]).body);});
 it('ingredient summary',()=>assert.equal(ingredientSummary([{name:'lohi',amount:.4,unit:'kg'},{name:'suola',amount:null,unit:''}]),'0,4 kg lohi, suola'));
});
describe('counts and ordering',()=>{
 it('splits left, bought and have',()=>assert.deepEqual(tripCounts([mark(false),mark(true),mark(false,true)],[mark(false),mark(true),mark(false,true)]),{left:2,bought:2,have:2,toBuy:4}));
 it('empty counts',()=>assert.deepEqual(tripCounts([],[]),{left:0,bought:0,have:0,toBuy:0}));
 it('all status variants',()=>{assert.equal(statusText({left:2,have:0,toBuy:3}),'2 / 3 jäljellä');assert.equal(statusText({left:2,have:4,toBuy:3}),'2 / 3 jäljellä · kotona 4');assert.equal(statusText({left:0,have:1,toBuy:3}),'Kaikki ostettu! 🎉 · kotona 1');assert.equal(statusText({left:0,have:2,toBuy:0}),'Kaikki on jo kotona');assert.equal(statusText({left:0,have:0,toBuy:0}),null);});
 it('stable order and old snapshots',()=>{const a={n:'a',...mark(true)},b={n:'b',...mark(false,true)},c={n:'c',...mark(false)},d={n:'d',...mark(false)};assert.deepEqual(historyOrder([a,b,c,d]).map(x=>x.n),['c','d','a','b']);assert.deepEqual(historyOrder([{n:'old',checked:true}]).map(x=>x.n),['old']);assert.deepEqual(uncheckedFirst([a,b,c,d]).map(x=>x.n),['b','c','d','a']);});
 it('have wins patches and false preserves other mark',()=>{assert.deepEqual(markClause(mark(false),{checked:true,have:true}),mark(false,true));assert.deepEqual(markClause(mark(false,true),{checked:false}),mark(false,true));assert.deepEqual(markClause(mark(true),{checked:false}),mark(false));});
 it('uses Helsinki day at UTC date boundary',()=>assert.equal(formatDay(Date.UTC(2026,9,18,22)), '19.10.2026'));
});
describe('aggregation and item state',()=>{
 it('case and NFC fold, JSON key has no separator collisions',()=>{assert.equal(fold('ÄITI'),'äiti');assert.equal(itemKey('Ma\u0308ito','DL'),itemKey('Mäito','dl'));assert.notEqual(itemKey('a,b','c'),itemKey('a','b,c'));});
 it('sums per unit, rounds, deduplicates dish names by id, keeps null',()=>{const rows=[{dishId:'1',dish:'A',name:'Kerma',amount:.1,unit:'dl'},{dishId:'1',dish:'A',name:'kerma',amount:.2,unit:'DL'},{dishId:'2',dish:'B',name:'kerma',amount:null,unit:'dl'},{dishId:'1',dish:'A',name:'kerma',amount:1,unit:'l'},{dishId:'1',dish:'A',name:'suola',amount:null,unit:''}];const items=aggregateIngredients(rows);assert.equal(items.length,3);assert.equal(items[0].amount,.3);assert.deepEqual(items[0].dishes,['A','B']);assert.equal(items[1].amount,1);assert.equal(items[2].amount,null);});
 it('edited amount pins null too, removed is separate, stale ignored',()=>{const g=aggregateIngredients([{dishId:'d',dish:'A',name:'kerma',amount:2,unit:'dl'}]);const result=applyItemState(g,{[g[0].key]:{edited:true,amount:null,removed:true,checked:false,have:false},stale:{checked:true}});assert.equal(result.items.length,0);assert.equal(result.removed[0].amount,null);assert.equal(result.removed[0].recipeAmount,2);assert.equal(applyItemState(g,{}).items[0].checked,false);});
});
describe('suggestions',()=>{
 const peruna={name:'peruna',unit:'kpl',uses:3},jauho={name:'perunajauho',unit:'dl',uses:1};
 it('only current answer; lone exact spelling hidden',()=>{assert.deepEqual(visibleSuggestions({query:'per',items:[peruna,jauho]},'per'),[peruna,jauho]);assert.deepEqual(visibleSuggestions({query:'pe',items:[peruna]},'per'),[]);assert.deepEqual(visibleSuggestions(null,'per'),[]);assert.deepEqual(visibleSuggestions({query:'peruna',items:[peruna]},'peruna'),[]);assert.deepEqual(visibleSuggestions({query:'Peruna',items:[peruna]},'Peruna'),[peruna]);assert.deepEqual(visibleSuggestions({query:'perun',items:[peruna]},'perun'),[peruna]);});
 const dishes=[{id:'a',name:'A',ingredients:[{name:' Peruna ',unit:' KPL ',amount:null},{name:'peruna',unit:'kg',amount:1},{name:'peruna',unit:'kpl',amount:2},{name:'perunajauho',unit:'dl',amount:1},{name:'bataattiperuna',unit:'',amount:null}]}];
 it('most frequent name/unit, whitespace and NFC, excludes nothing',()=>{assert.deepEqual(knownIngredients(dishes)[0],{key:'peruna',name:'peruna',unit:'kpl',uses:3});assert.deepEqual(suggestIngredients(dishes,' PER ')[0],peruna);});
 it('prefix before substring, frequency then alphabetical, bounded',()=>{assert.deepEqual(suggestIngredients(dishes,'per').map(x=>x.name),['peruna','perunajauho','bataattiperuna']);assert.equal(suggestIngredients(dishes,'',1).length,1);assert.deepEqual(suggestIngredients(dishes,'zz'),[]);const ties=[{id:'b',name:'B',ingredients:[{name:'Äiti',unit:'DL',amount:null},{name:'A\u0308iti',unit:'l',amount:null}]}];assert.equal(knownIngredients(ties)[0].uses,2);assert.equal(knownIngredients(ties)[0].unit,'dl');});
});

it('unit suggestions hide a lone exact match and retain partial matches', () => {
  const units = query => visibleSuggestions({ query, items: UNITS.filter(unit => unit.includes(query)).map(name => ({ name })) }, query);
  assert.deepEqual(units('dl'), []);
  assert.deepEqual(units('kg'), []);
  assert.deepEqual(units('nip'), [{ name: 'nippu' }]);
  assert.ok(units('').length > 1);
});
