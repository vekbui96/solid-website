import { ParentProps, createContext, createSignal, useContext } from "solid-js"

const globalContext = () => {
    const [activeSection, setActiveSection] = createSignal("hero");
    const [onDark, setOnDark] = createSignal(false);
    return { activeSection, setActiveSection, onDark, setOnDark };
}

const GlobalContext = createContext<ReturnType<typeof globalContext>>();

export const GlobalContextProvider = (props: ParentProps) => {
    const value = globalContext();
    return <GlobalContext.Provider value={value}>{props.children}</GlobalContext.Provider>
}

export const useGlobalContext = () => {
    return useContext(GlobalContext);
}
