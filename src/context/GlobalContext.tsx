import { ParentProps, createContext, createSignal, useContext } from "solid-js"

const globalContext = () => {
    const [activeSection, setActiveSection] = createSignal("hero");
    const [onDark, setOnDark] = createSignal(false);
    // set by the Fit Analyzer to deep-link/open a project in the showcase
    const [openProjectId, setOpenProjectId] = createSignal<string | null>(null);
    return { activeSection, setActiveSection, onDark, setOnDark, openProjectId, setOpenProjectId };
}

const GlobalContext = createContext<ReturnType<typeof globalContext>>();

export const GlobalContextProvider = (props: ParentProps) => {
    const value = globalContext();
    return <GlobalContext.Provider value={value}>{props.children}</GlobalContext.Provider>
}

export const useGlobalContext = () => {
    return useContext(GlobalContext);
}
