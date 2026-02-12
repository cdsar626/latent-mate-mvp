use crate::models::Question;
use uuid::Uuid;

pub fn get_questions() -> Vec<Question> {
    vec![
        Question {
            id: Uuid::new_v4(),
            text: "Would you rather have the ability to fly or be invisible?".to_string(),
            option_a: "Fly".to_string(),
            option_b: "Invisible".to_string(),
        },
        Question {
            id: Uuid::new_v4(),
            text: "Would you rather always be 10 minutes late or always be 20 minutes early?".to_string(),
            option_a: "10 mins late".to_string(),
            option_b: "20 mins early".to_string(),
        },
        Question {
            id: Uuid::new_v4(),
            text: "Would you rather lose all of your money and valuables or all of the pictures you have ever taken?".to_string(),
            option_a: "Lose Money".to_string(),
            option_b: "Lose Photos".to_string(),
        },
        Question {
            id: Uuid::new_v4(),
            text: "Would you rather have a rewind button or a pause button on your life?".to_string(),
            option_a: "Rewind".to_string(),
            option_b: "Pause".to_string(),
        },
        Question {
            id: Uuid::new_v4(),
            text: "Would you rather be able to talk with the animals or speak all foreign languages?".to_string(),
            option_a: "Talk with animals".to_string(),
            option_b: "Speak languages".to_string(),
        },
    ]
}
