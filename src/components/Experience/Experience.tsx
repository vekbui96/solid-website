import styles from './Experience.scss?inline'

type experienceType = {
    company: string;
    position: string;
    startDate: Date;
    endDate?: Date;
    description: string;
    acomplishments?: string;
    skills: string;
}

export const Experience = (props: experienceType) => {
    const accomplishment = (accomplishment: string) => {
        if (accomplishment !== undefined) {
            return <p>Accomplishments: {accomplishment}</p>
        }
    }
    return (
        <>
            <style>{styles}</style>
            <div class="experience-container">
                <h2>{props.company}</h2>
                <div class="experience-position-date">
                    <h2>{props.position}</h2>
                    <h3>{props.startDate.getFullYear()} - {props.endDate != undefined ? `${props.endDate}` : "Current"}</h3>
                </div>
                <h3 class="experience-description">{props.description}</h3>
                {accomplishment(props.acomplishments)}
                <p>Skills: {props.skills}</p>
            </div>
        </>
    )
}

export const ExperienceList = () => {
    return (
        <>
            <style>{styles}</style>
            <div class="experience-list">
                <Experience company="Capital One" position="Front end developer" startDate={new Date()} description="Sample Description" acomplishments="Nothing" skills="Java" />
                <Experience company="Capital One" position="Front end developer" startDate={new Date()} description="Sample Description" acomplishments="Nothing" skills="Java" />
            </div>
        </>
    )
}