import { ParentProps, createContext, createSignal } from "solid-js"

interface IGlobalContextProps {
    maybe?: number;
}

const globalContext = (props: ParentProps<IGlobalContextProps>) => {
    const [exampleContext, setExampleContext] = createSignal('');

    return {exampleContext,setExampleContext}
}

const GlobalContext = createContext<ReturnType<typeof globalContext>>();

export const GlobalContextProvider = (props: ParentProps<IGlobalContextProps>) => {
    const value = globalContext(props);
    return <GlobalContext.Provider value={value}>{props.children}</GlobalContext.Provider>
}