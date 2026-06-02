// @ts-ignore
import styles from "./About.scss?inline";
import about from "../../data/about.json";

export const About = () => {
    return (
        <>
            <style>{styles}</style>
            <section class="about-container">
                <h1 class="about-heading">About</h1>
                <p class="about-bio">{about.bio}</p>
            </section>
        </>
    );
};
