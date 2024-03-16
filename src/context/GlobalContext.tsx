import { ParentProps, createContext, createSignal, useContext} from "solid-js"

interface IGlobalContextProps {
    maybe?: number;
}

const globalContext = (props: ParentProps<IGlobalContextProps>) => {
    const [exampleContext, setExampleContext] = createSignal('response');
    const [page, setPage] = createSignal("hom");
    return {exampleContext,setExampleContext, page, setPage}
}

const GlobalContext = createContext<ReturnType<typeof globalContext>>();

export const GlobalContextProvider = (props: ParentProps<IGlobalContextProps>) => {
    const value = globalContext(props);
    return <GlobalContext.Provider value={value}>{props.children}</GlobalContext.Provider>
}

export const useGlobalContext = () => {
    return useContext(GlobalContext);
}