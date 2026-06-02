import styles from "./About.scss?inline";
import about from "../../data/about.json";

export const About = () => {
    return (
        <>
            <style>{styles}</style>
            <div class="about-container">
                <p>{about.bio}</p>
            </div>
        </>
    );
};
