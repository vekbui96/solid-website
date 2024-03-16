import { ExperienceList } from "../../components/Experience/Experience";
import styles from "./Home.scss?inline"


export const Home = () => {
    const startDate = new Date('January 30, 2020');
    const currentDate = new Date();
    

    return (
        <>
        <style>{styles}</style>
        <div class="home-container">
            <h1>{currentDate.getFullYear() - startDate.getFullYear()} years of experience</h1>

            <ExperienceList></ExperienceList>
        </div>
        </>
    )
}