import{i as n,c as l,e as x,t as o,S as g,b as w,I as T,f as A,g as L,o as q}from"./iframe-CiKs_OoT.js";import"./preload-helper-Ct5FWWRu.js";const E=".ui-rt{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:14px;max-width:520px}.ui-rt__step{display:flex;align-items:flex-start;gap:12px;opacity:.4;transition:opacity .3s ease}.ui-rt__step--active{opacity:1}.ui-rt__step--done{opacity:.8}.ui-rt__step--error{opacity:1}.ui-rt__dot{width:10px;height:10px;margin-top:5px;border-radius:50%;background:var(--border);flex-shrink:0;transition:background .3s ease}.ui-rt__step--active .ui-rt__dot{background:var(--accent);animation:ui-rt-pulse 1s ease-in-out infinite}.ui-rt__step--done .ui-rt__dot{background:var(--accent)}.ui-rt__step--error .ui-rt__dot{background:#f87171}.ui-rt__body{display:flex;flex-direction:column;gap:2px}.ui-rt__label{font-family:var(--font-mono);font-size:14px;color:var(--text)}.ui-rt__detail{font-size:13px;color:var(--muted)}.ui-rt__ellipsis{opacity:.7}.ui-rt__sr{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}@keyframes ui-rt-pulse{0%,to{box-shadow:0 0 #22d3ee00}50%{box-shadow:0 0 10px #22d3eeb3}}@media(prefers-reduced-motion:reduce){.ui-rt__step{transition:none}.ui-rt__step--active .ui-rt__dot{animation:none}}";var N=o("<style>"),k=o("<ol aria-live=polite>"),C=o("<span class=ui-rt__ellipsis aria-hidden=true>…"),I=o("<span class=ui-rt__sr> — done"),$=o("<span class=ui-rt__sr> — failed"),z=o("<span class=ui-rt__detail>"),F=o("<li class=ui-rt__step><span class=ui-rt__dot aria-hidden=true></span><span class=ui-rt__body><span class=ui-rt__label>");const m=i=>{const _=()=>["ui-rt",i.class].filter(Boolean).join(" ");return[(()=>{var s=N();return n(s,E),s})(),(()=>{var s=k();return n(s,l(T,{get each(){return i.steps},children:t=>{const e=()=>t().status??"pending";return(()=>{var a=F(),S=a.firstChild,v=S.nextSibling,p=v.firstChild;return n(p,()=>t().label,null),n(p,l(g,{get when(){return e()==="active"},get children(){return C()}}),null),n(p,l(g,{get when(){return e()==="done"},get children(){return I()}}),null),n(p,l(g,{get when(){return e()==="error"},get children(){return $()}}),null),n(v,l(g,{get when(){return t().detail},get children(){var r=z();return n(r,()=>t().detail),r}}),null),x(r=>{var h=e()==="active",b=e()==="done",f=e()==="error",y=e()==="active"?"step":void 0;return h!==r.e&&a.classList.toggle("ui-rt__step--active",r.e=h),b!==r.t&&a.classList.toggle("ui-rt__step--done",r.t=b),f!==r.a&&a.classList.toggle("ui-rt__step--error",r.a=f),y!==r.o&&w(a,"aria-current",r.o=y),r},{e:void 0,t:void 0,a:void 0,o:void 0}),a})()}})),x(t=>{var e=_(),a=i.label??"Reasoning steps";return e!==t.e&&A(s,t.e=e),a!==t.t&&w(s,"aria-label",t.t=a),t},{e:void 0,t:void 0}),s})()]};try{m.displayName="ReasoningTrace",m.__docgenInfo={description:`A live "thinking" / agent-step timeline: a vertical trace whose steps move
through pending → active → done (or error). Extracted from the site's Fit
Analyzer and generalized so it can narrate any agent run or tool sequence.

Accessibility: rendered as an ordered list with \`aria-live="polite"\` so
progress is announced, the active step carries \`aria-current="step"\`, and
done/error states have screen-reader-only text since the dot color is the
only visual cue.`,displayName:"ReasoningTrace",filePath:"C:/Users/tommy/Documents/projects/solid-website/src/ui/ReasoningTrace/ReasoningTrace.tsx",methods:[],props:{steps:{defaultValue:null,declarations:[{fileName:"solid-website/src/ui/ReasoningTrace/ReasoningTrace.tsx",name:"TypeLiteral"}],description:"",name:"steps",required:!0,tags:{},type:{name:"ReasoningStep[]"}},label:{defaultValue:null,declarations:[{fileName:"solid-website/src/ui/ReasoningTrace/ReasoningTrace.tsx",name:"TypeLiteral"}],description:"Accessible name for the list of steps.",name:"label",required:!1,tags:{},type:{name:"string"}},class:{defaultValue:null,declarations:[{fileName:"solid-website/src/ui/ReasoningTrace/ReasoningTrace.tsx",name:"TypeLiteral"}],description:"",name:"class",required:!1,tags:{},type:{name:"string"}}},tags:{}}}catch{}const B={title:"AI/ReasoningTrace",component:m},c={args:{label:"Fit analysis",steps:[{label:"Reading the role",status:"done",detail:"Parsed 14 requirements"},{label:"Mapping requirements to evidence",status:"done",detail:"9 projects matched"},{label:"Scoring fit & finding gaps",status:"active"},{label:"Drafting the summary",status:"pending"}]}},d={args:{label:"Agent run",steps:[{label:"Fetching corpus",status:"done"},{label:"Calling the model",status:"error",detail:"rate limited — retrying"},{label:"Scoring",status:"pending"}]}},R=["Reading the role","Extracting requirements","Mapping requirements to evidence","Scoring fit & finding gaps"],u={render:()=>{const[i,_]=L(0),s=setInterval(()=>_(e=>(e+1)%(R.length+2)),850);q(()=>clearInterval(s));const t=()=>R.map((e,a)=>({label:e,status:a<i()?"done":a===i()?"active":"pending"}));return l(m,{get steps(){return t()},label:"Analyzing fit"})}};c.parameters={...c.parameters,docs:{...c.parameters?.docs,source:{originalSource:`{
  args: {
    label: 'Fit analysis',
    steps: [{
      label: 'Reading the role',
      status: 'done',
      detail: 'Parsed 14 requirements'
    }, {
      label: 'Mapping requirements to evidence',
      status: 'done',
      detail: '9 projects matched'
    }, {
      label: 'Scoring fit & finding gaps',
      status: 'active'
    }, {
      label: 'Drafting the summary',
      status: 'pending'
    }]
  }
}`,...c.parameters?.docs?.source},description:{story:"A snapshot mid-run: two steps done, one running, one queued.",...c.parameters?.docs?.description}}};d.parameters={...d.parameters,docs:{...d.parameters?.docs,source:{originalSource:`{
  args: {
    label: 'Agent run',
    steps: [{
      label: 'Fetching corpus',
      status: 'done'
    }, {
      label: 'Calling the model',
      status: 'error',
      detail: 'rate limited — retrying'
    }, {
      label: 'Scoring',
      status: 'pending'
    }]
  }
}`,...d.parameters?.docs?.source},description:{story:"Error state — a failed step surfaces honestly instead of silently stalling.",...d.parameters?.docs?.description}}};u.parameters={...u.parameters,docs:{...u.parameters?.docs,source:{originalSource:`{
  render: () => {
    const [n, setN] = createSignal(0);
    const id = setInterval(() => setN(v => (v + 1) % (LABELS.length + 2)), 850);
    onCleanup(() => clearInterval(id));
    const steps = (): ReasoningStep[] => LABELS.map((label, i) => ({
      label,
      status: (i < n() ? 'done' : i === n() ? 'active' : 'pending') as ReasoningStatus
    }));
    return <ReasoningTrace steps={steps()} label="Analyzing fit" />;
  }
}`,...u.parameters?.docs?.source},description:{story:"Live run — steps advance automatically, the way the Fit Analyzer drives it.",...u.parameters?.docs?.description}}};const D=["MixedStates","WithError","Live"];export{u as Live,c as MixedStates,d as WithError,D as __namedExportsOrder,B as default};
