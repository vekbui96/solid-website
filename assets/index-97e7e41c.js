(function(){const t=document.createElement("link").relList;if(t&&t.supports&&t.supports("modulepreload"))return;for(const i of document.querySelectorAll('link[rel="modulepreload"]'))s(i);new MutationObserver(i=>{for(const o of i)if(o.type==="childList")for(const l of o.addedNodes)l.tagName==="LINK"&&l.rel==="modulepreload"&&s(l)}).observe(document,{childList:!0,subtree:!0});function n(i){const o={};return i.integrity&&(o.integrity=i.integrity),i.referrerPolicy&&(o.referrerPolicy=i.referrerPolicy),i.crossOrigin==="use-credentials"?o.credentials="include":i.crossOrigin==="anonymous"?o.credentials="omit":o.credentials="same-origin",o}function s(i){if(i.ep)return;i.ep=!0;const o=n(i);fetch(i.href,o)}})();const X=(e,t)=>e===t,R=Symbol("solid-proxy"),M={equals:X};let Y=V;const m=1,$=2,k={owned:null,cleanups:null,context:null,owner:null};var p=null;let j=null,J=null,a=null,d=null,b=null,P=0;function Z(e,t){const n=a,s=p,i=e.length===0,o=t===void 0?s:t,l=i?k:{owned:null,cleanups:null,context:o?o.context:null,owner:o},r=i?e:()=>e(()=>N(()=>B(l)));p=l,a=null;try{return S(r,!0)}finally{a=n,p=s}}function x(e,t,n){const s=q(e,t,!1,m);T(s)}function E(e,t,n){n=n?Object.assign({},M,n):M;const s=q(e,t,!0,0);return s.observers=null,s.observerSlots=null,s.comparator=n.equals||void 0,T(s),ee.bind(s)}function N(e){if(a===null)return e();const t=a;a=null;try{return e()}finally{a=t}}function z(e){const t=E(e),n=E(()=>D(t()));return n.toArray=()=>{const s=n();return Array.isArray(s)?s:s!=null?[s]:[]},n}function ee(){if(this.sources&&this.state)if(this.state===m)T(this);else{const e=d;d=null,S(()=>_(this),!1),d=e}if(a){const e=this.observers?this.observers.length:0;a.sources?(a.sources.push(this),a.sourceSlots.push(e)):(a.sources=[this],a.sourceSlots=[e]),this.observers?(this.observers.push(a),this.observerSlots.push(a.sources.length-1)):(this.observers=[a],this.observerSlots=[a.sources.length-1])}return this.value}function te(e,t,n){let s=e.value;return(!e.comparator||!e.comparator(s,t))&&(e.value=t,e.observers&&e.observers.length&&S(()=>{for(let i=0;i<e.observers.length;i+=1){const o=e.observers[i],l=j&&j.running;l&&j.disposed.has(o),(l?!o.tState:!o.state)&&(o.pure?d.push(o):b.push(o),o.observers&&W(o)),l||(o.state=m)}if(d.length>1e6)throw d=[],new Error},!1)),t}function T(e){if(!e.fn)return;B(e);const t=P;ne(e,e.value,t)}function ne(e,t,n){let s;const i=p,o=a;a=p=e;try{s=e.fn(t)}catch(l){return e.pure&&(e.state=m,e.owned&&e.owned.forEach(B),e.owned=null),e.updatedAt=n+1,G(l)}finally{a=o,p=i}(!e.updatedAt||e.updatedAt<=n)&&(e.updatedAt!=null&&"observers"in e?te(e,s):e.value=s,e.updatedAt=n)}function q(e,t,n,s=m,i){const o={fn:e,state:s,updatedAt:null,owned:null,sources:null,sourceSlots:null,cleanups:null,value:t,owner:p,context:p?p.context:null,pure:n};return p===null||p!==k&&(p.owned?p.owned.push(o):p.owned=[o]),o}function K(e){if(e.state===0)return;if(e.state===$)return _(e);if(e.suspense&&N(e.suspense.inFallback))return e.suspense.effects.push(e);const t=[e];for(;(e=e.owner)&&(!e.updatedAt||e.updatedAt<P);)e.state&&t.push(e);for(let n=t.length-1;n>=0;n--)if(e=t[n],e.state===m)T(e);else if(e.state===$){const s=d;d=null,S(()=>_(e,t[0]),!1),d=s}}function S(e,t){if(d)return e();let n=!1;t||(d=[]),b?n=!0:b=[],P++;try{const s=e();return re(n),s}catch(s){n||(b=null),d=null,G(s)}}function re(e){if(d&&(V(d),d=null),e)return;const t=b;b=null,t.length&&S(()=>Y(t),!1)}function V(e){for(let t=0;t<e.length;t++)K(e[t])}function _(e,t){e.state=0;for(let n=0;n<e.sources.length;n+=1){const s=e.sources[n];if(s.sources){const i=s.state;i===m?s!==t&&(!s.updatedAt||s.updatedAt<P)&&K(s):i===$&&_(s,t)}}}function W(e){for(let t=0;t<e.observers.length;t+=1){const n=e.observers[t];n.state||(n.state=$,n.pure?d.push(n):b.push(n),n.observers&&W(n))}}function B(e){let t;if(e.sources)for(;e.sources.length;){const n=e.sources.pop(),s=e.sourceSlots.pop(),i=n.observers;if(i&&i.length){const o=i.pop(),l=n.observerSlots.pop();s<i.length&&(o.sourceSlots[l]=s,i[s]=o,n.observerSlots[s]=l)}}if(e.owned){for(t=e.owned.length-1;t>=0;t--)B(e.owned[t]);e.owned=null}if(e.cleanups){for(t=e.cleanups.length-1;t>=0;t--)e.cleanups[t]();e.cleanups=null}e.state=0}function se(e){return e instanceof Error?e:new Error(typeof e=="string"?e:"Unknown error",{cause:e})}function G(e,t=p){throw se(e)}function D(e){if(typeof e=="function"&&!e.length)return D(e());if(Array.isArray(e)){const t=[];for(let n=0;n<e.length;n++){const s=D(e[n]);Array.isArray(s)?t.push.apply(t,s):t.push(s)}return t}return e}function A(e,t){return N(()=>e(t||{}))}function C(){return!0}const oe={get(e,t,n){return t===R?n:e.get(t)},has(e,t){return t===R?!0:e.has(t)},set:C,deleteProperty:C,getOwnPropertyDescriptor(e,t){return{configurable:!0,enumerable:!0,get(){return e.get(t)},set:C,deleteProperty:C}},ownKeys(e){return e.keys()}};function L(e){return(e=typeof e=="function"?e():e)?e:{}}function ie(){for(let e=0,t=this.length;e<t;++e){const n=this[e]();if(n!==void 0)return n}}function le(...e){let t=!1;for(let l=0;l<e.length;l++){const r=e[l];t=t||!!r&&R in r,e[l]=typeof r=="function"?(t=!0,E(r)):r}if(t)return new Proxy({get(l){for(let r=e.length-1;r>=0;r--){const f=L(e[r])[l];if(f!==void 0)return f}},has(l){for(let r=e.length-1;r>=0;r--)if(l in L(e[r]))return!0;return!1},keys(){const l=[];for(let r=0;r<e.length;r++)l.push(...Object.keys(L(e[r])));return[...new Set(l)]}},oe);const n={},s=Object.create(null);for(let l=e.length-1;l>=0;l--){const r=e[l];if(!r)continue;const f=Object.getOwnPropertyNames(r);for(let c=f.length-1;c>=0;c--){const u=f[c];if(u==="__proto__"||u==="constructor")continue;const h=Object.getOwnPropertyDescriptor(r,u);if(!s[u])s[u]=h.get?{enumerable:!0,configurable:!0,get:ie.bind(n[u]=[h.get.bind(r)])}:h.value!==void 0?h:void 0;else{const g=n[u];g&&(h.get?g.push(h.get.bind(r)):h.value!==void 0&&g.push(()=>h.value))}}}const i={},o=Object.keys(s);for(let l=o.length-1;l>=0;l--){const r=o[l],f=s[r];f&&f.get?Object.defineProperty(i,r,f):i[r]=f?f.value:void 0}return i}function fe(e,t,n){let s=n.length,i=t.length,o=s,l=0,r=0,f=t[i-1].nextSibling,c=null;for(;l<i||r<o;){if(t[l]===n[r]){l++,r++;continue}for(;t[i-1]===n[o-1];)i--,o--;if(i===l){const u=o<s?r?n[r-1].nextSibling:n[o-r]:f;for(;r<o;)e.insertBefore(n[r++],u)}else if(o===r)for(;l<i;)(!c||!c.has(t[l]))&&t[l].remove(),l++;else if(t[l]===n[o-1]&&n[r]===t[i-1]){const u=t[--i].nextSibling;e.insertBefore(n[r++],t[l++].nextSibling),e.insertBefore(n[--o],u),t[i]=n[o]}else{if(!c){c=new Map;let h=r;for(;h<o;)c.set(n[h],h++)}const u=c.get(t[l]);if(u!=null)if(r<u&&u<o){let h=l,g=1,I;for(;++h<i&&h<o&&!((I=c.get(t[h]))==null||I!==u+g);)g++;if(g>u-r){const Q=t[l];for(;r<u;)e.insertBefore(n[r++],Q)}else e.replaceChild(n[r++],t[l++])}else l++;else t[l++].remove()}}}function ue(e,t,n,s={}){let i;return Z(o=>{i=o,t===document?e():y(t,e(),t.firstChild?null:void 0,n)},s.owner),()=>{i(),t.textContent=""}}function v(e,t,n){let s;const i=()=>{const l=document.createElement("template");return l.innerHTML=e,n?l.content.firstChild.firstChild:l.content.firstChild},o=t?()=>N(()=>document.importNode(s||(s=i()),!0)):()=>(s||(s=i())).cloneNode(!0);return o.cloneNode=o,o}function H(e,t,n){n==null?e.removeAttribute(t):e.setAttribute(t,n)}function y(e,t,n,s){if(n!==void 0&&!s&&(s=[]),typeof t!="function")return O(e,t,s,n);x(i=>O(e,t(),i,n),s)}function O(e,t,n,s,i){for(;typeof n=="function";)n=n();if(t===n)return n;const o=typeof t,l=s!==void 0;if(e=l&&n[0]&&n[0].parentNode||e,o==="string"||o==="number")if(o==="number"&&(t=t.toString()),l){let r=n[0];r&&r.nodeType===3?r.data!==t&&(r.data=t):r=document.createTextNode(t),n=w(e,n,s,r)}else n!==""&&typeof n=="string"?n=e.firstChild.data=t:n=e.textContent=t;else if(t==null||o==="boolean")n=w(e,n,s);else{if(o==="function")return x(()=>{let r=t();for(;typeof r=="function";)r=r();n=O(e,r,n,s)}),()=>n;if(Array.isArray(t)){const r=[],f=n&&Array.isArray(n);if(F(r,t,n,i))return x(()=>n=O(e,r,n,s,!0)),()=>n;if(r.length===0){if(n=w(e,n,s),l)return n}else f?n.length===0?U(e,r,s):fe(e,n,r):(n&&w(e),U(e,r));n=r}else if(t.nodeType){if(Array.isArray(n)){if(l)return n=w(e,n,s,t);w(e,n,null,t)}else n==null||n===""||!e.firstChild?e.appendChild(t):e.replaceChild(t,e.firstChild);n=t}}return n}function F(e,t,n,s){let i=!1;for(let o=0,l=t.length;o<l;o++){let r=t[o],f=n&&n[o],c;if(!(r==null||r===!0||r===!1))if((c=typeof r)=="object"&&r.nodeType)e.push(r);else if(Array.isArray(r))i=F(e,r,f)||i;else if(c==="function")if(s){for(;typeof r=="function";)r=r();i=F(e,Array.isArray(r)?r:[r],Array.isArray(f)?f:[f])||i}else e.push(r),i=!0;else{const u=String(r);f&&f.nodeType===3&&f.data===u?e.push(f):e.push(document.createTextNode(u))}}return i}function U(e,t,n=null){for(let s=0,i=t.length;s<i;s++)e.insertBefore(t[s],n)}function w(e,t,n,s){if(n===void 0)return e.textContent="";const i=s||document.createTextNode("");if(t.length){let o=!1;for(let l=t.length-1;l>=0;l--){const r=t[l];if(i!==r){const f=r.parentNode===e;!o&&!l?f?e.replaceChild(i,r):e.insertBefore(i,n):f&&r.remove()}else o=!0}}else e.insertBefore(i,n);return[i]}const ae=`.header{margin:0;justify-content:space-between;align-items:flex-start;position:fixed;top:0;width:100%;z-index:30;transition-duration:.4s;padding:2px}.container{margin:0;background-color:#202020}.subHeader{margin:0;flex:auto;justify-content:space-between;align-items:center}
`,ce=[{id:1,name:"Home",href:"hero"},{id:2,name:"About",href:"about"},{id:3,name:"Portfolio",href:"portfolio"},{id:4,name:"Contact",href:"contact"}],he=e=>{const t=z(()=>e.children);return le(e,{get children(){return t()}})};var de=v("<nav class=ect><ul class=boxes>"),pe=v("<li>"),ge=v('<a target=_blank class="block text-white font-medium text-sm relative cursor-pointer after:duration-300 after:content-[attr(data-hover)] after:absolute after:left-1/2 after:top-3/4 after:opacity-0 after:-translate-x-1/2 hover:after:top-1/2 hover:after:opacity-100 after:hover:-translate-x-1/2 after:hover:-translate-y-1/2"><span class=item>'),ye=v("<span class=item>");const be="before:absolute before:h-[6px] before:w-[6px] before:rounded-full before:bg-white before:left-1/2 before:-translate-x-1/2 before:-bottom-3",me="after:content-[attr(data-hover)] after:absolute after:left-1/2 after:top-3/4 after:opacity-0 after:-translate-x-1/2 hover:after:top-1/2 hover:after:opacity-100 after:hover:-translate-x-1/2 after:hover:-translate-y-1/2",ve=()=>(()=>{var e=de(),t=e.firstChild;return y(t,()=>ce.map(n=>(()=>{var s=pe();return y(s,(()=>{var i=E(()=>!!n.href);return()=>i()?(()=>{var o=ge(),l=o.firstChild;return y(l,()=>n.name),x(r=>{var f=n.href,c=n.name.toLowerCase();return f!==r.e&&H(o,"href",r.e=f),c!==r.t&&H(o,"data-hover",r.t=c),r},{e:void 0,t:void 0}),o})():A(he,{spy:!0,smooth:!0,get to(){return n.href},activeClass:be,get"data-hover"(){return n.name.toLowerCase()},className:`block text-white font-medium text-sm relative cursor-pointer after:duration-300 ${me}`,get children(){var o=ye();return y(o,()=>n.name),o}})})()),x(()=>H(s,"key",n.id)),s})())),e})();var we=v("<style>"),xe=v('<header class=header>Ve Bui<div class=container><div class=subHeader><div class="flex items-center justify-between"><span class=sm:hidden>');const Ae=()=>[(()=>{var e=we();return y(e,ae),e})(),(()=>{var e=xe(),t=e.firstChild,n=t.nextSibling,s=n.firstChild;return s.firstChild,y(s,A(ve,{}),null),e})()];var Se=v('<section class=heroBackground><div class=heroBackground2><div class="mt-8 font-light"><h1 class=name>Tommy Bui</h1><h2 class=profession>SOFTWARE DEV');const Ce=()=>Se(),$e=()=>[A(Ae,{}),A(Ce,{})];ue(()=>A($e,{}),document.getElementById("app"));