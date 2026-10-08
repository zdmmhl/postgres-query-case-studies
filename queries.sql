-- Q1:  gives all the level-5 and level-7 subjects that are offered at least twice by the ‘School’ type organizations in 2012.  And the organization’s name should contain ‘Engineering’.subject_code should be taken from Subjects.code field.  
create or replace view Q1(subject_code) as
SELECT s.code AS subject_code
FROM Subjects s
JOIN Courses c ON s.id = c.subject
JOIN Semesters sem ON c.semester = sem.id
JOIN Orgunits o ON s.offeredby = o.id
JOIN Orgunit_types ot ON o.utype = ot.id
WHERE (s.code LIKE '____5___' OR s.code LIKE '____7___') -- Level-5 or Level-7
    AND sem.year = 2012 -- Offered in 2012
    AND ot.name LIKE '%School%' -- which cotain "School"
    AND o.longname LIKE '%Engineering%' -- which cotain "Engineering"
GROUP BY s.code
HAVING COUNT(*) >= 2;
--------------------------------------------------------------------------

-- Q2:  Define an SQL view Q2(course_id) that gives the ID of the course offering at least 'Lecture' and 'Laboratory' classes. Only consider the course that has at least two professors as staff and offers exactly two lectures in two distinct rooms.
create or replace view Q2(course_id) as
WITH CourseClasses AS (
  SELECT 
    c.id AS course_id,
    COUNT(CASE WHEN ct.name = 'Lecture' THEN 1 END) AS lecture_count, 
    COUNT(DISTINCT CASE WHEN ct.name = 'Lecture' THEN cl.room END) AS lecture_rooms,
    COUNT(CASE WHEN ct.name = 'Laboratory' THEN 1 END) AS lab_count
  FROM Courses c
  JOIN Classes cl ON c.id = cl.course --do join late!
  JOIN Class_types ct ON cl.ctype = ct.id
  GROUP BY c.id
),
CourseProfessors AS (
  SELECT 
    cs.course AS course_id,
    COUNT(DISTINCT p.id) AS prof_count
  FROM Course_staff cs
  JOIN Staff s ON cs.staff = s.id
  JOIN People p ON s.id = p.id
  WHERE p.title LIKE 'Prof'
  GROUP BY cs.course
)
SELECT cc.course_id
FROM CourseClasses cc
JOIN CourseProfessors cp ON cc.course_id = cp.course_id
WHERE cc.lecture_count = 2            -- 2 Lecture
  AND cc.lecture_rooms = 2            -- 2 distinct rooms
  AND cc.lab_count >= 1               -- at least 1 Laboratory room
  AND cp.prof_count >= 2;    -- At least two professors for the course
--------------------------------------------------------------------------

--Q3:  Define a SQL view Q3(unsw_id) that gives the unswid of students who are enrolled in the 'Major', 'Minor', and 'Honours' streams simultaneously within the same program. The student’s unswid starts with 326.

create or replace view Q3(unsw_id) as
SELECT p.unswid AS unsw_id
FROM People p
JOIN Students s ON p.id = s.id
JOIN Program_enrolments pe ON s.id = pe.student
JOIN Stream_enrolments se ON pe.id = se.partof
JOIN Streams st ON se.stream = st.id
JOIN Stream_types stt ON st.stype = stt.id
WHERE p.unswid >= 3260000 AND p.unswid < 3270000  -- Ensure the student's unswid starts with 326
  AND stt.description IN ('Major', 'Minor', 'Honours')  -- Filter for Major, Minor, and Honours streams
GROUP BY p.unswid
HAVING COUNT(DISTINCT stt.description) = 3;  -- Ensure the student has all three streams: Major, Minor, and Honours
--------------------------------------------------------------------------

--Q4 :  Define an SQL view Q4(course_id, avg_mark) that gives the course ID along with the average mark of master’s students who achieved a pass in each course. For each faculty and for each year between 2005 and 2015, it includes only those courses that have the highest average pass mark among all courses offered by that Faculty in that year. If multiple courses have the same maximum average mark in that year, all such courses are included.

CREATE OR REPLACE VIEW Q4(course_id, avg_mark) AS
WITH 
-- select Master students
MasterStudents AS (
    SELECT DISTINCT 
        pe.student,
        pe.semester
    FROM Program_enrolments pe
    JOIN Program_degrees pd ON pe.program = pd.program
    JOIN Degree_types dt ON pd.dtype = dt.id 
    WHERE dt.name LIKE 'Master%'
),
-- check all pass marks
PassMarks AS (
    SELECT 
        ce.student,
        ce.mark,
        c.id AS course_id,
        c.semester
    FROM Course_enrolments ce
    JOIN Courses c ON ce.course = c.id 
    WHERE ce.mark >= 50
),
-- compute avg pass marks
PassAvg AS (
    SELECT 
        pm.course_id,
        AVG(pm.mark) AS raw_avg,       
        s.year,
        o.id AS faculty_id
    FROM PassMarks pm
    JOIN Courses c ON pm.course_id = c.id
    JOIN Semesters s ON c.semester = s.id
    JOIN MasterStudents ms             
        ON pm.student = ms.student 
        AND pm.semester = ms.semester  -- !!!! should be the same semester the unmaster students may change their degree into master
    JOIN Subjects sub ON c.subject = sub.id
    JOIN Orgunits o ON sub.offeredby = o.id
    JOIN Orgunit_types ot ON o.utype = ot.id 
    WHERE s.year BETWEEN 2005 AND 2015
      AND ot.name = 'Faculty'
    GROUP BY pm.course_id, s.year, o.id
),
-- compute max pass marks on faculty and year
MaxAvg AS (
    SELECT 
        year,
        faculty_id,
        MAX(raw_avg) AS max_raw_avg
    FROM PassAvg
    GROUP BY year, faculty_id
)
SELECT 
    pa.course_id,
    ROUND(pa.raw_avg::numeric, 2) AS avg_mark 
FROM PassAvg pa
JOIN MaxAvg ma 
    ON pa.year = ma.year 
    AND pa.faculty_id = ma.faculty_id
    AND pa.raw_avg = ma.max_raw_avg;          
--------------------------------------------------------------------------

--Question 5 (5 marks) Define a SQL view Q5(course_id, student_names, highest_mark) that gives the ID of course which enrolled more than 500 students in year between 2005 and 2015. Show the highest mark achieved by any student in the course. And the given names of the students who achieved this highest mark. If multiple students share the highest mark, their given names are concatenated in order, separated by "; " (e.g., "Jack;  Michele"). 

CREATE OR REPLACE VIEW Q5(course_id, student_names, highest_mark) AS
WITH 
-- select courses which have more than 500 students
CourseSelect AS (
    SELECT 
        c.id AS course_id
    FROM Courses c
    JOIN Semesters s ON c.semester = s.id
    JOIN Course_enrolments ce ON c.id = ce.course
    WHERE s.year BETWEEN 2005 AND 2015
    GROUP BY c.id
    HAVING COUNT(DISTINCT ce.student) > 500  -- de-weight the students
), 

--calculate the highest mark for each course
MaxMarks AS (
    SELECT 
        ce.course AS course_id,
        MAX(ce.mark) AS highest_mark
    FROM Course_enrolments ce
    JOIN CourseSelect cs ON ce.course = cs.course_id
    GROUP BY ce.course
),

--get the students who achieved the highest mark in each course
StudentNames AS (
    SELECT 
        ce.course AS course_id,
        p.given AS given_name,
        ce.mark
    FROM Course_enrolments ce
    JOIN People p ON ce.student = p.id
    JOIN MaxMarks mm 
        ON ce.course = mm.course_id 
        AND ce.mark = mm.highest_mark  -- match with the highest mark
)

SELECT 
    mm.course_id,
    STRING_AGG(sn.given_name, '; ' ORDER BY sn.given_name),
    mm.highest_mark
FROM MaxMarks mm
LEFT JOIN StudentNames sn ON mm.course_id = sn.course_id
GROUP BY mm.course_id, mm.highest_mark;
--------------------------------------------------------------------------

--Question 6 (5 marks)  Define SQL view Q6(subject_id, year, room_id, usage_count) to return the ID of each subject that used the largest number of distinct rooms in each year between 2000 and 2015, along with the room ID(s) that the subject used most frequently and the number of times the subject used that room. If there are multiple subjects or rooms with the same maximum usage, list all of them. 

CREATE OR REPLACE VIEW Q6(subject_id, year, room_id, usage_count) AS
WITH 
-- calculate the number of distinct rooms used by each subject in each year
SubjectRoomCounts AS (
    SELECT 
        s.id AS subject_id,
        sem.year,
        COUNT(DISTINCT cl.room) AS room_count
    FROM Subjects s
    JOIN Courses c ON s.id = c.subject
    JOIN Semesters sem ON c.semester = sem.id  -- set which year
    JOIN Classes cl ON c.id = cl.course     -- join classes to get room info
    WHERE sem.year BETWEEN 2000 AND 2015
    GROUP BY s.id, sem.year
),

-- calculate the maximum number of distinct rooms used by any subject in each year
MaxRoomCountsPerYear AS (
    SELECT 
        year,
        MAX(room_count) AS max_rooms
    FROM SubjectRoomCounts src
    GROUP BY year
),

-- find subjects that used the maximum number of distinct rooms in each year
QualifiedSubjects AS (
    SELECT 
        src.subject_id,
        src.year
    FROM SubjectRoomCounts src
    JOIN MaxRoomCountsPerYear mrc 
        ON src.year = mrc.year 
        AND src.room_count = mrc.max_rooms
),

-- calculate the usage count of each room for each subject in each year
RoomUsageDetails AS (
    SELECT 
        s.id AS subject_id,
        sem.year AS year,
        cl.room AS room_id,
        COUNT(*) AS usage_count  -- count for each room usage
    FROM Subjects s
    JOIN Courses c ON s.id = c.subject
    JOIN Semesters sem ON c.semester = sem.id
    JOIN Classes cl ON c.id = cl.course
    WHERE sem.year BETWEEN 2000 AND 2015
    GROUP BY s.id, sem.year, cl.room
),

-- find the maximum usage count for each subject in each year
MaxUsagePerSubject AS (
    SELECT 
        subject_id,
        year,
        MAX(usage_count) AS max_usage
    FROM RoomUsageDetails
    GROUP BY subject_id, year
)

SELECT 
    rud.subject_id,
    rud.year,
    rud.room_id,
    rud.usage_count
FROM RoomUsageDetails rud
JOIN QualifiedSubjects qs 
    ON rud.subject_id = qs.subject_id 
    AND rud.year = qs.year
JOIN MaxUsagePerSubject mus 
    ON rud.subject_id = mus.subject_id
    AND rud.year = mus.year 
    AND rud.usage_count = mus.max_usage;
--------------------------------------------------------------------------

--Question 7 (6 marks)  Define SQL view Q7(student_id, orgunit_id, program_id, obtain_days) that gives the IDs of students who completed a program in the shortest time for each organization. The completed program is offered by the organization. If multiple students achieve the same fastest completion time, all such students are included. If multiple courses share the same subject code with a pass, you can treat them as distinct subjects. For example, some research courses (for instance, honours thesis A/B/C) must be enrolled in multiple times but share the same subject code.

CREATE OR REPLACE VIEW Q7(student_id, orgunit_id, program_id, obtain_days) AS
WITH 
--calculate the total UOC and obtain days for each student in each program
ProgramDetail AS (
    SELECT
        p.unswid AS student_id,
        o.id AS orgunit_id, 
        pr.id AS program_id,
        SUM(CASE WHEN ce.mark >= 50 THEN sub.uoc ELSE 0 END) AS total_uoc,
        MAX(sem.ending) - MIN(sem.starting) AS obtain_days
    FROM People p
    JOIN Students s ON p.id = s.id
    JOIN Program_enrolments pe ON s.id = pe.student
    JOIN Programs pr ON pe.program = pr.id
    JOIN Orgunits o ON o.id = pr.offeredby
    JOIN Course_enrolments ce ON s.id = ce.student
    JOIN Courses c ON ce.course = c.id 
        AND c.semester = pe.semester -- same as q4, should be the same semester
    JOIN Subjects sub ON c.subject = sub.id
    JOIN Semesters sem ON c.semester = sem.id
    GROUP BY p.unswid, o.id, pr.id
    HAVING SUM(CASE WHEN ce.mark >= 50 THEN sub.uoc ELSE 0 END) >= pr.uoc
),
-- calculate the minimum obtain days for each organization
MinDays AS (
    SELECT 
        student_id, 
        orgunit_id, 
        program_id, 
        obtain_days,
        RANK() OVER (PARTITION BY orgunit_id ORDER BY obtain_days) AS rnk
    FROM ProgramDetail
)
SELECT student_id, orgunit_id, program_id, obtain_days
FROM MinDays
WHERE rnk = 1; --who took 1st means the shortest time 
--------------------------------------------------------------------------
--Question 8 (6 marks)  Define SQL view Q8(staff_id, student_id, teach_times) This view retrieves the staff ID (staff_id) of those who served as a course convenor at least three times in the years between 2008 and 2012. Additionally, the total ‘above distinction’ rate (i.e., the percentage of students with marks ≥ 75) across all courses in history where the staff member as a course convenor must be ≥ 70%. For each such staff member, the view also returns the student ID (student_id) of those who enrolled in courses where the mentioned staff served but may not as a course convenor, along with the number of times (teach_times) the student enrolled in those courses across their entire enrollment history.  The result must include only the top-2 students with the highest teach_times (i.e., enrollment count). Additionally, only students with teach_times ≥ 3 should be displayed.

CREATE OR REPLACE VIEW Q8(staff_id, student_id, teach_times) AS
WITH 
-- select the staff who served as course convenor at least 3 times between 2008 and 2012
ConvenorCourses AS (
    SELECT 
        cs.staff, 
        COUNT(DISTINCT c.id) AS convenor_count
    FROM Course_staff cs
    JOIN Staff_roles sr ON cs.role = sr.id
    JOIN Courses c ON cs.course = c.id
    JOIN Semesters sem ON c.semester = sem.id
    WHERE sr.name = 'Course Convenor'
        AND sem.year BETWEEN 2008 AND 2012
    GROUP BY cs.staff
    HAVING COUNT(DISTINCT c.id) >= 3
), 

-- calculate the above distinction rate for each staff
AboveDistinctionRate AS (
    SELECT 
        cs.staff, 
        COUNT(CASE WHEN ce.mark >= 75 THEN 1 END)::FLOAT / COUNT(ce.mark) AS distinction_rate
    FROM Course_staff cs
    JOIN Staff_roles sr ON cs.role = sr.id
    JOIN Course_enrolments ce ON cs.course = ce.course
    WHERE sr.name = 'Course Convenor'
        AND ce.mark IS NOT NULL
    GROUP BY cs.staff
    HAVING COUNT(CASE WHEN ce.mark >= 75 THEN 1 END)::FLOAT / COUNT(ce.mark) >= 0.7
),

-- select the staff who meet the rate
QualifiedStaff AS (
    SELECT DISTINCT c.staff
    FROM ConvenorCourses c
    JOIN AboveDistinctionRate adr ON c.staff = adr.staff
),

-- calculate the number of times each student enrolled in courses where the staff served
StudentEnrollments AS (
    SELECT 
        ce.student,
        cs.staff, 
        COUNT(*) AS teach_times
    FROM Course_staff cs
    JOIN QualifiedStaff qs ON cs.staff = qs.staff
    JOIN Course_enrolments ce ON cs.course = ce.course
    GROUP BY ce.student, cs.staff
    HAVING COUNT(*) >= 3
),

-- rank the students based on their enrollment count
RankedStudents AS (
    SELECT 
        se.staff, 
        se.student, 
        se.teach_times,
        RANK() OVER (PARTITION BY se.staff ORDER BY se.teach_times DESC) AS rnk
    FROM StudentEnrollments se
)

-- use people.unswid
SELECT 
    p1.unswid AS staff_id,
    p2.unswid AS student_id, 
    rs.teach_times
FROM RankedStudents rs
JOIN People p1 ON rs.staff = p1.id
JOIN People p2 ON rs.student = p2.id
WHERE rs.rnk <= 2;
----------------------------------------------------------------------------

--Question 9 (6 marks) Define a PL/pgSQL function Q9(unswsid integer) This function takes a student's unswid as input and returns the given name of the student's favorite teacher—defined as the course convenor whose courses the student has enrolled in the most times (Note: different with Q8). Additionally, the function returns: 1) The number of times the student has enrolled in courses convened by this teacher. 2) The rank of the student based on how many times they have enrolled in the teacher’s courses compared to other students.

CREATE OR REPLACE FUNCTION Q9(unswid integer) RETURNS SETOF TEXT 
AS $$
DECLARE
    student_id      integer;
    valid_student   boolean;
    max_count       integer;
    rec             record;
    student_rank    integer;
BEGIN
    -- get valid student ID
    SELECT p.id, EXISTS (
        SELECT 1 
        FROM Course_enrolments 
        WHERE student = p.id AND mark IS NOT NULL
    ) INTO student_id, valid_student
    FROM People p
    WHERE p.unswid = Q9.unswid;
    -- if not valid student
    IF student_id IS NULL OR NOT valid_student THEN
        RETURN NEXT 'WARNING: Invalid Student Input ' || '[' || Q9.unswid || ']';
        RETURN;
    END IF;

    -- caculated the number of times each teacher has been enrolled 
    WITH 
    UniqueConvenors AS (
        SELECT DISTINCT 
            cs.course, 
            cs.staff
        FROM Course_staff cs
        JOIN Staff_roles sr ON cs.role = sr.id
        WHERE sr.name = 'Course Convenor'
    ),
    TeacherCounts AS (
        SELECT 
            p.id AS staff_id,
            p.given,
            COUNT(DISTINCT c.id) AS cnt
        FROM Course_enrolments ce
        JOIN Courses c ON ce.course = c.id
        JOIN UniqueConvenors uc ON c.id = uc.course
        JOIN People p ON uc.staff = p.id
        WHERE ce.student = student_id
          AND ce.mark IS NOT NULL
        GROUP BY p.id, p.given
    ),
    MaxCount AS (
        SELECT MAX(cnt) AS max_cnt FROM TeacherCounts
    )
    SELECT max_cnt INTO max_count FROM MaxCount;

    -- if this student has no course
    IF max_count IS NULL OR max_count = 0 THEN
        RETURN NEXT 'WARNING: Invalid Student Input ' || '[' || Q9.unswid || ']';
        RETURN;
    END IF;

    -- loop through each teacher with the maximum count number
    FOR rec IN 
        WITH 
        UniqueConvenors AS (
            SELECT DISTINCT 
                cs.course, 
                cs.staff
            FROM Course_staff cs
            JOIN Staff_roles sr ON cs.role = sr.id
            WHERE sr.name = 'Course Convenor'
        ),
        TeacherCounts AS (
            SELECT 
                p.id AS staff_id,
                p.given,
                COUNT(DISTINCT c.id) AS cnt
            FROM Course_enrolments ce
            JOIN Courses c ON ce.course = c.id
            JOIN UniqueConvenors uc ON c.id = uc.course
            JOIN People p ON uc.staff = p.id
            WHERE ce.student = student_id
                AND ce.mark IS NOT NULL
         GROUP BY p.id, p.given
        )
        SELECT tc.given, tc.cnt
        FROM TeacherCounts tc
        WHERE tc.cnt = max_count
    LOOP
        WITH 
        UniqueConvenors AS (
            SELECT DISTINCT 
                cs.course, 
                cs.staff
            FROM Course_staff cs
            JOIN Staff_roles sr ON cs.role = sr.id
            WHERE sr.name = 'Course Convenor'
        ),
        RankData AS (
            SELECT 
                ce.student,
                p.id AS staff_id,
                p.given AS teacher_given,
                COUNT(DISTINCT c.id) AS enrollments,
                RANK() OVER (
                    PARTITION BY p.id  --- Rank by teacher's ID not name
                    ORDER BY COUNT(DISTINCT c.id) DESC --for each course,maybe a course has multiple teachers
                ) AS global_rank
            FROM course_enrolments ce
            JOIN courses c ON ce.course = c.id
            JOIN UniqueConvenors uc ON c.id = uc.course
            JOIN people p ON uc.staff = p.id
            WHERE ce.mark IS NOT NULL
            GROUP BY ce.student, p.id, p.given
        )
        SELECT global_rank INTO student_rank
        FROM RankData
        WHERE student = student_id 
          AND teacher_given = rec.given;

        RETURN NEXT rec.given || ' ' || rec.cnt || ' ' || student_rank;
    END LOOP;

    RETURN;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NEXT 'WARNING: Invalid Student Input ' || '[' || Q9.unswid || ']';
        RETURN;
END;
$$ LANGUAGE plpgsql;
--------------------------------------------------------------------------

--Question 10 (7 marks)  Define a PL/pgSQL function Q10(unswid integer) that takes the unswid of a student. Output the students WAM for all the programs that the student enrolled.

CREATE OR REPLACE FUNCTION Q10(unswid integer) RETURNS SETOF TEXT 
AS $$
DECLARE
    student_id      integer;
    has_programs    boolean;
    rec             record;
    wam_result      numeric;
    total_weighted  numeric;
    total_uoc       numeric;
    pass_grades     text[] := ARRAY['SY','PT','PC','PS','CR','DN','HD','A','B','C','XE','T','PE','RC','RS'];
    excluded_grades text[] := ARRAY['SY','XE','T','PE'];
BEGIN
    -- get student ID
    SELECT id INTO student_id 
    FROM People p
    WHERE p.unswid = Q10.unswid;

    -- if valid student
    IF student_id IS NULL THEN
        RETURN NEXT 'WARNING: Invalid Student Input ' || '[' || Q10.unswid || ']';
        RETURN;
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM Program_enrolments 
        WHERE student = student_id
    ) INTO has_programs;

    IF NOT has_programs THEN
        RETURN NEXT 'WARNING: Invalid Student Input ' ||'[' || Q10.unswid || ']';
        RETURN;
    END IF;

    -- loop through each program to calculate WAM
    FOR rec IN 
        SELECT 
            p.unswid,
            pr.name AS program_name,
            pr.id AS program_id
        FROM Program_enrolments pe
        JOIN Programs pr ON pe.program = pr.id
        JOIN People p ON pe.student = p.id
        WHERE pe.student = student_id
        GROUP BY p.unswid, pr.name, pr.id
    LOOP
        -- distinguish pass_grades and excluded_grades
        SELECT 
            SUM(ce.mark * s.uoc),
            SUM(s.uoc)
        INTO 
            total_weighted,
            total_uoc
        FROM Program_enrolments pe
        JOIN Courses c ON pe.semester = c.semester
        JOIN Course_enrolments ce ON c.id = ce.course 
            AND pe.student = ce.student
        JOIN Subjects s ON c.subject = s.id
        WHERE pe.student = student_id
          AND pe.program = rec.program_id
          AND ce.mark IS NOT NULL
          AND (
              ce.grade IS NULL 
              OR 
              ce.grade <> ALL(pass_grades)
              OR 
              (ce.grade = ANY(pass_grades) AND ce.grade <> ALL(excluded_grades))
          );

        -- Use a space to distinguish between 3 values
        IF total_uoc IS NULL OR total_uoc = 0 THEN
            RETURN NEXT rec.unswid || ' ' || rec.program_name || ' No WAM Available';
        ELSE
            wam_result := ROUND((total_weighted / total_uoc)::numeric, 2);
            RETURN NEXT rec.unswid || ' ' || rec.program_name || ' ' || wam_result;
        END IF;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;
