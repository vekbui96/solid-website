// @ts-ignore
import styles from "./Projects.scss?inline";

export const Projects = () => {
    return (
        <>
            <style>{styles}</style>
            <div class="content">
                <section class="projects-container">
                    <h1 class="projects-heading">Projects</h1>
                    <p class="projects-intro">A selection of work is on the way.</p>
                    <div class="projects-empty">Selected projects coming soon.</div>
                </section>
            </div>
        </>
    );
};
